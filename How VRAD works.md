# BSP format
The following is the VDC information on the BSP lighting lump:

> The lighting lump (Lump 8) is used to store the static lightmap samples of map faces. Each lightmap sample is a colour tint that multiplies the colours of the underlying texture pixels, to produce lighting of varying intensity. These lightmaps are created during the VRAD phase of map compilation and are referenced from the `dface_t` structure. The current lighting lump version is 1.
> Each `dface_t` may have a up to four lightstyles defined in its `styles[]` array (which contains `255` to represent no lightstyle). The number of luxels in each direction of the face is given by the two `LightmapTextureSizeInLuxels[]` members (plus 1), and the total number of luxels per face is thus:
> ```
> (LightmapTextureSizeInLuxels[0] + 1) * (LightmapTextureSizeInLuxels[1] + 1)
> ```
> Each face gives a byte offset into the lighting lump in its `lightofs` member (if no lighting information is used for this face e.g. faces with skybox, nodraw and invisible textures, `lightofs` is `-1`.) There are `(number of lightstyles)*(number of luxels)` lightmap samples for each face, where each sample is a 4-byte `ColorRGBExp32` structure:
> ```
> struct ColorRGBExp32
> {
>     byte r, g, b;
>     signed char exponent;
> };
> ```
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
												^ Lightofs indexes to here.
```

# Sampling Process
Though technical details are still lacking at this point (I've yet to look closely enough), the general process for calculating the lighting on a face is to split that face into sampling points as per the number of luxels, and then sample the lighting at each of these points. This involves finding out how much each of the visible lights contributes to each sample. The BSP's VIS information is used in this process to cull away any lights that will not affect the given face, and falloff formulae are used to work out how much to attenuate the colour of each light, depending on how far away it is.

This process appears that it may be easily parallelisable: each face's lighting samples can be computed independently of each other, and indeed the same can be said for each face in general.

# VRAD Data Structures

VRAD is pretty much written in C-style C++, so it's not as easy as it could be to trace through the logic. Below are some of the core data structures that are involved in the process.

## directlight_t *(vrad.h:66)*

Represents a basic light. In terms of entities, this can be a `light`, `light_spot` or `light_environment`.

**Trivia:** Light classnames are parsed by VRAD depending on whether they begin with the prefix "light". `light_dynamic` is then manually excluded in code.

```
struct directlight_t
{
	int index;              // Identifier for this light. (?)

	directlight_t *next;	// Next direct light in the linked list of lights created by VRAD so far.
	dworldlight_t light;    // Corresponding "world" light (ie. light settings from the BSP). (?)

	byte *pvs;              // Valve: "Accumulated domain of the light." All the VIS information this light can see.
	int facenum;	        // Valve: "Domain of attached lights." ?
	int texdata;	        // Valve: "Texture source of traced lights." ?

	Vector	snormal;        // Unit vector in the S axis. (?)
	Vector	tnormal;        // Unit vector in the T axis. (?)
	float sscale;           // Scale of S axis.
	float tscale;           // Scale of T axis.
	float soffset;          // Offset of light origin along S axis. TODO: Before or after scale?
	float toffset;          // Offset of light origin along T axis. TODO: Before or after scale?

	int dorecalc;           // Valve: "Position, vector, spot angle, etc." ?
	IncrementalLightID	m_IncrementalID;    // ?

	// Valve: "Hard-falloff lights (lights that fade to an actual zero). Between m_flStartFadeDistance and
	// m_flEndFadeDistance, a smoothstep to zero will be done, so that the light goes to zero at
	// the end."
	float m_flStartFadeDistance;
	float m_flEndFadeDistance;
	float m_flCapDist;      // Valve: "Max distance to feed in."

    // Default constructor.
	directlight_t(void)
	{
		m_flEndFadeDistance = -1.0; // Valve: "End < start indicates not set."
		m_flStartFadeDistance= 0.0;
		m_flCapDist = 1.0e22;
	}
};
```