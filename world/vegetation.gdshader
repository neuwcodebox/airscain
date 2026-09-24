shader_type spatial;
render_mode diffuse_burley;
// Vertex alpha marks foliage that takes the per-instance tint; trunks keep their color.
varying vec3 tint;

void vertex() {
	tint = mix(vec3(1.0), INSTANCE_CUSTOM.rgb, COLOR.a);
}

void fragment() {
	ALBEDO = COLOR.rgb * tint;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
