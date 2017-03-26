#Introduction

The documents present in the `documentation` folder of the repository provide some background information and technical details about radiosity simulation. To summarise the important points, radiosity algorithms generally proceed by dividing up the scene into "patches", where a patch is an area with a uniform illumination. Within the context of the Source engine and VRAD, patches can be considered "pixels" in a level's lightmap, and correspond to "luxels" on a face.

It should be noted that in certain algorithms, patches are subdivided (ie. split up into smaller parts) where it can be determined that the increased density is desirable. For example, to have a sharper, less blocky shadow cast on a surface, that surface should be divided up into more patches.

For `n` patches, the radiosity of patch `i` can be given as follows:

```
Bi = Ei + Pi * SUMj(Bj * Fij)
```

* `Bi` is the radiosity of patch `i`, where `i` is between `1` and `n`.
* `Ei` is the emissivity of patch `i`, ie. how much light the patch gives off.
* `Pi` is the reflectivity of patch `i`, ie. how much light the patch reflects. This is a vector of values between `0` and `1`.
* `SUMj()` is the sum of the terms for all `j`, where `j` is some other patch from `1` to `n`.
* `Bj` is the radiosity of patch `j`.
* `Fij` is the "form factor". This is a measure of the proportion of light emitted from patch `j` that reaches patch `i`, as a value between `0` and `1`.

Each term apart from `Fij` can be represented as a 3-dimensional vector, representing an RGB colour where each term is between `0` and `1`. `Fij` is just used as a multiplier to reduce the contribution of the radiosity from patch `j`. `Pj` can similarly be considered a vector of multipliers for each of the R, G and B elements of the result of the sum.

Combining the equations of all of the patches into a single matrix, the radiosity of each patch can be computed iteratively (see documentation). This, however, occupies a lot of space in memory (which can slow things down if hard disk paging has to occur) and makes it difficult to preview things: if you want to see the results, you have to run the algorithm all the way through to completion.

The "Progressive Refinement" method allows a partial run of the algorithm to be displayed and then for subsequent runs to "refine" the result. This works by "shooting" the light from the patch with the most radiosity in each run, which over a small number of runs will give a rough approximation of the lighting as a whole. Many more iterations are required in order to correctly compute the subtler details of the illumination.

Memory-wise, the matrix method uses an amount of memory that is an order of magnitude larger than (ie. the square of) the memory used by progressive refinement. This means that by using the latter method, much more complex scenes can be computed with the same amount of RAM.

# Core Algorithm

To light a level, VRAD logic begins in `RunVRAD()`, though the heavy lifting mostly happens one level lower in `RadWorld_Go()`. The summary of the non-MPI process, assuming all lighting features are requested, is as follows:

```
Load the BSP and other resources, eg. lights.rad
Initialise various data structures.

Make a single patch for each face.
Recursively subdivide each patch int children, until the children are smaller
    than the chop size in all axes.

Initialise the macro texture.

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
# Definitions
Some of the terms and concepts used within the VRAD simulation are as follows:

## Chop
The following definitions are made within the code:

* `maxchop`: Coarsest allowed number of luxel widths for a patch.
* `minchop`: Tightest number of luxel widths for a patch, used on edges.

## Macro Texture
`macro_texture.h` provides some information:

> The macro texture looks for a TGA file with the same name as the BSP file and in the same directory. If it finds one, it maps this texture onto the world dimensions (in the worldspawn entity) and masks all lightmaps with it.

From `SampleMacroTexture()`, the world position is used to sample the macro texture. On the X and Y axes, a position of `world_mins` corresponds to texture pixel `0`, and a position of `world_maxs` corresponds to texture pixel `dimension-1`. It is assumed that the texture dimensions begin from the upper left.

Once the texture sample location is computed, the alpha value from the texture is used in `ApplyMacroTextures()` to mask the colour of a given luxel. A value of `255` in the texture corresponds to no masking, whereas a value of `0` corresponds to complete masking (ie. an output of `[0 0 0]`).

## Patch
[This Black Mesa forum post](https://forums.blackmesasource.com/index.php/Thread/28869-Texture-Lights-and-Bounce-lighting-in-VRAD/) gives an overview of how VRAD works, within the context of giving the program new lighting parameters:

> VRAD "chops" the BSP surfaces into "patches" that get the calculated lighting. The patches act as the pixels of the light map, so to speak. VRAD chops up surfaces according to the lightmap size set in Hammer, takes the light brightness values from each patch, and raytraces that data to every other patch in a huge matrix, using fancy physics based falloff calculations. When texture lights are used, these patches are set to be bright, and give off light.
>
> By default, VRAD is set to ignore the chopping of surfaces that have flagged unlit materials. It is set this way to save compile time, because surfaces that don't receive lighting (such as nodraw and water, etc.) don't need to have detailed lightmaps.

As per the `CPatch` definition, each patch has a single parent and a maximum of two children. This implies that patches are structured in a binary tree. It is normal within code to see patches be excluded from lighting simulations if they are not leaves (ie. if they have any children).

Patches are different

Some insightful uses of patches within the code (with function signatures modified for readability) are:

* `MakePatchForFace(faceNumber, winding)` *(vrad.cpp:534)*

    Called by `MakePatches()`. The face begins by having a single patch created, and the chop scale is computed according to the texture scale and is stored in the patch's `luxscale`. The patch's `chop` value, however, is just set to `maxchop`.

* `CreateChildPatch(parentIndex, winding, area, centre)` *(vrad.cpp:767)*

    **TODO: Complete this description.**

* `CreateDirectLights()` *(lightmap.cpp:1541)*

    If the amount of light emitted by a patch is greater than a given threshold, a *direct light* is created for the patch. This is used for textures that should emit light, where each patch on the surface of the textured face corresponds to a source of light.

* `AddSampleToPatch(sample, light, faceNumber)` *(lightmap.cpp:2060)*

    All patches that belong to the specified face are iterated over. For each leaf patch, its `samplelight` value is increased if the given sample is determined to fall within the bounds of the patch. The colour and intensity of the accumulated light is provided by the `light` function argument, and this is multiplied by the amount of surface area the sample covers.

* `BuildPatchLights(faceNumber)` *(lightmap.cpp:3196)*

    This function calls `AddSampleToPatch()` as above for each sample on the face, using the sample number to index into the `facelight_t` structure for the given face. It then adjusts the accumulated light values so that parent patches reflect the sum of the values of their children. After this, it averages patch lighting according to area, and transfers `totallight` into `directlight`.

## Sample
A face is cut into samples, which have a position, normal and area. There are as many samples on a face as there are luxels. Samples don't seem to actually store light information - this is what a patch is for.

In code, samples are relevant in the following areas:

* `BuildFacesamples(lightInfo, faceLight)` *(lightmap.cpp:650)*

    Splits a face up into samples, along the lightmap splitting axes (which are in luxel space). There are `luxelsOnS * luxelsOnT` samples created. The world position of each sample is stored within it.

* `AddSampleToPatch(sample, light, faceNumber)` *(lightmap.cpp:2060)*

    Same purpose as described within the definition for a patch.
        
* `SupersampleLightAtPoint(lightInfo, sampleInfo, sampleIndex, lightStyleIndex,`
    `lightingValue, flags)` *(lightmap.cpp:2683)*

    Given a sample index, computes new sample points and normals, and recalculates the lighting for the lightingValue passed in.

## Lighting Value


# VRAD Data Structures

VRAD is pretty much written in C-style C++, so it's not as easy as it could be to trace through the logic. Below are some of the core data structures that are involved in the process.

##  dworldlight_t *(bspfile.h:966)*

Seems to represent a light in the BSP, as opposed to a light in VRAD. The difference is that VRAD lights contain references to simulation-specific information, which would be irrelevant to the game engine. *(TODO: Confirm this inference is valid.)*

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

As described on the Black Mesa forum page, a patch represents "a pixel of the light map". It looks like a given face is divided up into many patches, and each patch corresponds to some kind of "cell" that accumulates light.

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