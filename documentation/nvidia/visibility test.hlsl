bool Visible(half3 ProjPos,            // camera-space pos of element
             uniform fixed3 RecvID,    // ID of receiver, for item buffer
             sampler2D HemiItemBuffer )
{
	// Project the texel element onto the hemisphere
	half3 proj = normalize(ProjPos);

	// Vector is in [-1,1], scale to [0..1] for texture lookup
	proj.xy = proj.xy * 0.5 + 0.5;

	// Look up projected point in hemisphere item buffer
	fixed3 xtex = tex2D(HemiItemBuffer, proj.xy);

	// Compare the value in item buffer to the ID of the fragment
	return all(xtex == RecvID);
}
