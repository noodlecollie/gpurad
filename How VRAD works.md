# BSP format

The following is the [VDC information on the BSP lighting lump](https://developer.valvesoftware.com/wiki/Source_BSP_File_Format#Lighting):

> The lighting lump (Lump 8) is used to store the static lightmap samples of map faces. Each lightmap sample is a colour tint that multiplies the colours of the underlying texture pixels, to produce lighting of varying intensity. These lightmaps are created during the VRAD phase of map compilation and are referenced from the `dface_t` structure. The current lighting lump version is 1.
> Each `dface_t` may have a up to four lightstyles defined in its `styles[]` array (which contains `255` to represent no lightstyle). The number of luxels in each direction of the face is given by the two `LightmapTextureSizeInLuxels[]` members (plus 1), and the total number of luxels per face is thus:

```
(LightmapTextureSizeInLuxels[0] + 1) * (LightmapTextureSizeInLuxels[1] + 1)
```

> Each face gives a byte offset into the lighting lump in its `lightofs` member (if no lighting information is used for this face e.g. faces with skybox, nodraw and invisible textures, `lightofs` is `-1`.) There are `(number of lightstyles)*(number of luxels)` lightmap samples for each face, where each sample is a 4-byte `ColorRGBExp32` structure:

```
struct ColorRGBExp32
{
    byte r, g, b;
    signed char exponent;
};
```

> Standard RGB format can be obtained from this by multiplying each colour component by `2^(exponent)`. For faces with bumpmapped textures, there are four times the usual number of lightmap samples, presumably containing samples used to compute the bumpmapping.
> Immediately preceeding the lightofs-referenced sample group, there are single samples containing the average lighting on the face, one for each lightstyle, in reverse order from that given in the `styles[]` array.
> Version 20 BSP files contain a second, identically sized lighting lump (Lump 53). This is presumed to store more accurate (higher-precision) HDR data for each lightmap sample. The format is currently unknown, but is also 32 bits per sample.
> The maximum size of the lighting lump is `0x1000000` bytes, i.e. 16 Mb (`MAX_MAP_LIGHTING`).

The data format can therefore be thought of as being laid out in the following way:

```
Sample             : 4 bytes
Lightstyles        : 4
Luxels             : 17x17 = 289
Samples            : 289 x 4 = 1156
Samples occupy     : 4624 bytes
Avg samples        : 4
Avg samples occupy : 16 bytes
Lightofs           : n

n-16        n-12        n-8         n-4         n           n+4         n+8
|Avg Sample3|Avg Sample2|Avg Sample1|Avg Sample0|  Sample0  |  Sample1  |  ...
                                                ^ Lightofs indexes to here
```

# VRAD Internals

The Black Mesa mod crew have made some modifications to VRAD for their own use, and [the forum page](https://forums.blackmesasource.com/index.php/Thread/28869-Texture-Lights-and-Bounce-lighting-in-VRAD/) detailing the new commands helps shed some light (ha ha) on some of the concepts involved in the simulation:

> Vrad "chops" the bsp surfaces into "patches" that get the calculated lighting. The patches act as the pixels of the light map so to speak. Vrad chops up surfaces according to the lightmap size, set in hammer. Vrad takes the light brightness values from each patch, and raytraces that data to every other patch in a large huge matrix; also using fancy physics based falloff calculations. When texture lights are used, these patches are set to be bright, and give off light.
>
> By default, vrad is set to ignore the chopping of surfaces that have flagged unlit materials. It is set this way to save compile time, because surfaces that don't receive lighting (such as nodraw and water, etc.) don't need to have detailed lightmaps.

# Core Algorithm

The actual VRAD logic begins in `RunVRAD()`, though the heavy lifting mostly happens one level lower in `RadWorld_Go()`. The summary of the non-MPI process, assuming all lighting features are requested, is as follows:

```
Load the BSP.
Initialise a macro texture. (TODO: What's this?)

If performing incremental light simulation:
    Prepare for incremental lighting.
    Determine which faces are visible to which lights.
Otherwise:
    Mark all faces potentially visible to lights.

Sample lighting for all faces.
Compute lightmap data offsets for each face (see BSP lightmap data format).

If performing incremental light simulation:
    Finalise lighting.
    Exit.

Export direct lights to world lights.

If computing light bounces:
    Compute transfers for visleaves. (TODO: What on earth is this?)
    Bounce light between patches, adding to their accumulated light.

Accumulate light for displacements.
Combine indirect lighting with direct lighting.
Compute detail prop lighting.
Compute ambient lighting for leaves.

If computing static prop lighting:
    Compute static prop lighting.

Write results out to BSP.
```


# VRAD Data Structures

VRAD is pretty much written in C-style C++, so it's not as easy as it could be to trace through the logic. Below are some of the core data structures that are involved in the process.

##  dworldlight_t *(bspfile.h:966)*

Seems to represent a light in the BSP, as opposed to a light in VRAD. The difference is that VRAD lights contain references to simulation-specific information, which would be irrelevant to the game engine.

```c++
struct dworldlight_t
{
    DECLARE_BYTESWAP_DATADESC();    // Not sure what this is for, or whether it's relevant
                                    // for VRAD.
    Vector      origin;             // Position of the light in the world.
    Vector      intensity;          // Unclear whether this contains the brightness of the
                                    // light as well, or just the colour.
    Vector      normal;             // Valve: "For surfaces and spotlights."
    int         cluster;            // Which vis cluster this light belongs to?
    emittype_t  type;               // What type of light this is: point, spot, etc. See the
                                    // emittype_t enum.
    int         style;              // What style this light uses?
    float       stopdot;            // Valve: "Start of penumbra for emit_spotlight." Probably
                                    // named after the dot product.
    float       stopdot2;           // Valve: "End of penumbra for emit_spotlight."
    float       exponent;           // Something to do with light brightness?
    float       radius;             // Valve: "Cutoff distance." Assuming after this distance
                                    // in any direction, the light doesn't affect surfaces.

    // Valve: "Falloff for emit_spotlight + emit_point: 
    // 1 / (constant_attn + linear_attn * dist + quadratic_attn * dist^2)"

    float       constant_attn;  // Constant coefficient in the above formula.
    float       linear_attn;    // Linear coefficient in the above formula. This is the
                                // brightness that is affected by distance.
    float       quadratic_attn; // Quadratic coefficient in the above formula. This is the
                                // brightness that is affected by the square of the distance.
    int         flags;          // Uses a combination of the DWL_FLAGS_ defines.
    int         texinfo;        // Not sure.
    int         owner;          // Valve: "Entity that this light it relative to."
};
```

## directlight_t *(vrad.h:66)*

Represents a basic light. In terms of entities, this can be a `light`, `light_spot` or `light_environment`.

**Trivia:** Light classnames are parsed by VRAD depending on whether they begin with the prefix "light". `light_dynamic` is then manually excluded in code.

```c++
struct directlight_t
{
    int index;              // Identifier for this light. (?)

    directlight_t* next;    // Next direct light in the linked list of lights created by VRAD
                            // so far.
    dworldlight_t light;    // Corresponding "world" light (ie. light settings from the BSP).

    byte* pvs;              // Valve: "Accumulated domain of the light." All the VIS
                            // information this light can see.
    int facenum;            // Valve: "Domain of attached lights." ?
    int texdata;            // Valve: "Texture source of traced lights." ?

    Vector snormal;         // Unit vector in the S axis. (?)
    Vector tnormal;         // Unit vector in the T axis. (?)
    float sscale;           // Scale of S axis.
    float tscale;           // Scale of T axis.
    float soffset;          // Offset of light origin along S axis. TODO: Before or after scale?
    float toffset;          // Offset of light origin along T axis. TODO: Before or after scale?

    int dorecalc;                           // Valve: "Position, vector, spot angle, etc." ?
    IncrementalLightID  m_IncrementalID;    // ?

    // Valve: "Hard-falloff lights (lights that fade to an actual zero). Between
    // m_flStartFadeDistance and m_flEndFadeDistance, a smoothstep to zero will be done,
    // so that the light goes to zero at the end."
    float m_flStartFadeDistance;    // In units?
    float m_flEndFadeDistance;      // In units?
    float m_flCapDist;              // Valve: "Max distance to feed in." Assuming this is a
                                    // manual override that can truncate brightness before
                                    // m_flEndFadeDistance is reached.

    // Default constructor.
    directlight_t(void)
    {
        m_flEndFadeDistance = -1.0; // Valve: "End < start indicates not set."
        m_flStartFadeDistance= 0.0;
        m_flCapDist = 1.0e22;
    }
};
```

## CPatch *(vrad.h:186)*

Not entirely sure what a patch is, but my best guess is that it's VRAD's internal luxel-based representation of a face.

```c++
struct CPatch
{
    winding_t* winding;     // Harks back to the Quake days. This is a (theoretically)
                            // infinite plane that may have been clipped down to an
                            // arbitrary size and shape. Is always convex.
    Vector mins;            // The minimum point in 3D space for this patch.
    Vector maxs;            // The maximum point in 3D space for this patch. The axis-aligned
                            // box (mins, maxs) defines the AABB for the patch.
    Vector face_mins;       // Minimum point in 3D space of the original face?
    Vector face_maxs;       // Maximum point in 3D space of the original face?

    Vector origin;          // Valve: "Adjusted off face by face normal." Is this local or
                            // global space?

    dplane_t* plane;        // Valve: "Plane (corrected for facing)." Plane that the winding
                            // lies in; not sure what "corrected for facing" means.
    
    unsigned short      m_IterationKey; // Valve: "Used to prevent touching the same patch
                                        // multiple times in the same query.
                                        // See IncrementPatchIterationKey()."
    
    // Valve: "These are packed into one dword."
    unsigned int normalMajorAxis : 2;   // Valve" "The major axis of base face normal."
                                        // This is probably 0, 1 or 2 - confirm.
    unsigned int sky : 1;               // Whether this patch is sky or not.
    unsigned int needsBumpmap : 1;      // Whether this patch needs bump-mapped lighting?
    unsigned int pad : 28;              // Padding (?)

    Vector normal;              // Valve: "Adjusted for phong shading." Assuming this means
                                // it's interpolated between other normals.

    float planeDist;            // Valve: "Fixes up patch planes for brush models with an
                                // origin brush." ?

    float chop;                 // Valve: "Smallest acceptable width of patch face."
    float luxscale;             // Valve: "Average luxels per world coord."
    float scale[2];             // Valve: "Scaling of texture in S & T."

    bumplights_t totallight;    // Valve: "Accumulated by radiosity. Does NOT include light
                                // accounted for by direct lighting."
    Vector baselight;           // Valve: "Emissivity only." Assuming colour of emitted light.
    float basearea;             // Valve: "Surface per area per baselight instance." ?

    Vector directlight;         // Valve: "Direct light value." ?
    float area;                 // Total area of patch?

    Vector reflectivity;        // Valve: "Average RGB of texture, modified by material type."

    Vector samplelight;         // ?
    float samplearea;           // Valve: "For averaging direct light." Area covered by
                                // samples?
    int faceNumber;             // ID of the face this patch relates to?
    int clusterNumber;          // ID of the VIS cluster this patch relates to?

    int parent;                 // Valve: "Patch index of parent."
    int child1;                 // Valve: "Patch index for children." Assuming a binary
    int child2;                 // tree of patches.

    int ndxNext;                // Valve: "Next patch index in face." Faces have multiple
                                // patches?
    int ndxNextParent;          // Valve: "Next parent patch index in face." ?
    int ndxNextClusterChild;    // Valve: "Next terminal child index in cluster." ?

    int numtransfers;           // ?
    transfer_t* transfers;      // ? Even looking up transfer_t isn't very helpful.

    short indices[3];           // Valve: "Displacement use these for subdivision." Power of 2
                                // to subdivide the patch in eaxh axis?
};
```
