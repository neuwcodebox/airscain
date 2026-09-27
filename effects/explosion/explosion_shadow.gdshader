shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

varying flat uint camera_layers;
varying flat float selected;

void vertex() {
	camera_layers = CAMERA_VISIBLE_LAYERS;
	selected = INSTANCE_ID % 4 == 0 ? 1.0 : 0.0;
	if (selected < 0.5) { VERTEX = vec3(0.0); }
}

void fragment() {
	if (camera_layers != uint(524288) || selected < 0.5 || COLOR.a < 0.12) { discard; }
	vec3 encoded = fract((1.0 - FRAGCOORD.z) * vec3(1.0, 255.0, 65025.0));
	encoded -= encoded.yzz * vec3(1.0 / 255.0, 1.0 / 255.0, 0.0);
	ALBEDO = encoded;
}
