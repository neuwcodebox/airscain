shader_type spatial;
uniform float night_amount = 0.0;
uniform vec4 damaged_buildings[4]; // center XZ, half extents XZ
uniform int damaged_building_count = 0;
varying float occupancy;
varying float powered;
void vertex() {
	occupancy = fract(sin(float(INSTANCE_ID) * 127.1 + 17.0) * 43758.5453);
	powered = 1.0;
	for (int i = 0; i < damaged_building_count; i++) {
		vec4 bounds = damaged_buildings[i];
		if (all(lessThanEqual(abs(MODEL_MATRIX[3].xz - bounds.xy), bounds.zw))) {
			powered = 0.0;
		}
	}
}
void fragment() {
	ALBEDO = vec3(0.149, 0.235, 0.282);
	METALLIC = 0.22;
	ROUGHNESS = 0.3;
	float lit = smoothstep(0.28, 0.42, occupancy);
	vec3 warm = mix(vec3(1.0, 0.49, 0.16), vec3(1.0, 0.81, 0.48), occupancy);
	EMISSION = mix(vec3(0.038, 0.089, 0.113), warm * lit * 1.5, night_amount) * powered;
}
