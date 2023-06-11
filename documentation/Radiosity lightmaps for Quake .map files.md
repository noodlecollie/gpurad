https://www.reddit.com/r/GraphicsProgramming/comments/vqz4b4/radiosity_lightmaps_for_quake_map_files/

This is a continuation on a previous post I made about getting .map files loaded and making a basic lightmapper for them.

This week I added radiosity, which is an older global illumination technique that Quake 2, the source engine, and others used. Basically, the world is divided into small patches (those obvious pixels in the first map), then a "form factor" is computed between them which determines how much energy is transferred which is based on area, distance, angle and occlusion. The radiosity equation says that the radiosity of one patch is equal to the sum of all the others times their form factor.

One way to solve this is by iterating over all the patches and distributing the current estimate of radiosity for the patch. One flaw with it though is it that computing all the form factors is O(n2), so it really slows down when the patch count gets above like 30,000. But for the most part it's pretty fast to compile the maps. Looking through Quakes QRAD and Valves VRAD we're a big help in getting it to work right.

Anyways I'm happy with how it all turned out, and I think this is a good stopping point for this project.

> very interesting, I always thought they will use some sort of raytracing to generate a lightmap.
>
> Is the radiosity information stored per patch or as a lightmap?

Oh it still uses ray tracing.

The lightmap process is basically in 2 parts, first you have the direct lighting part. A bunch of sample points are generated across each map face (these sample points are the final lightmap pixels), with some checks to make sure they aren't in walls. Then from each sample, I shoot a ray to all light sources if it's within their radius. That determines the direct lighting.

Indirect patches though aren't related to the samples but rather to the faces. So to connect the 2, each sample is then checked against all face patches and added to the ones inside the bounds. Then each patch does the full radiosity process outside of the concept of the final lightmap (which also uses ray casts to test if 2 patches can see each other).

However this raises the issue of getting the patches (which are super low res compared to the final pixels) to the lightmap. Quake 2 used a triangulation method of basically converting the patches into a triangle mesh to interpolate for each sample. I tried this and it was really garbage; slow, didn't look good, complicated code. So I did what Valve did in VRAD, which is really simple honestly, just loop through all the sample points and add the patch lighting along with a weight if it's in it's radius.

So the final patches are in the lightmap pixels, that first clip with the patches was just a debug mesh.
