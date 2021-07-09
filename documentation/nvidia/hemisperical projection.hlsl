void hemiwarp(float4 Position: POSITION,     // pos in world space
              uniform half4x4 ModelView,     // modelview matrix
              uniform half2 NearFar,         // near and far planes
              out float4 ProjPos: POSITION)  // projected position
{
	// transform the geometry to camera space
	half4 mpos = mul(ModelView, Position);

	// project to a point on a unit hemisphere
	half3 hemi_pt = normalize( mpos.xyz );

	// Compute (f-n), but let the hardware divide z by this
	// in the w component (so premultiply x and y)
	half f_minus_n = NearFar.y - NearFar.x;
	ProjPos.xy = hemi_pt.xy * f_minus_n;

	// compute depth proj. independently, using OpenGL orthographic
	ProjPos.z = (-2.0 * mpos.z - NearFar.y - NearFar.x);
	ProjPos.w = f_minus_n;
}
