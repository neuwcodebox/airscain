shader_type spatial;
render_mode diffuse_burley;

varying vec3 terrain_position;
varying vec3 terrain_normal;

void vertex() {
	terrain_position = VERTEX;
	terrain_normal = NORMAL;
}

void fragment() {
	float h = terrain_position.y;
	float slope = 1.0 - clamp(normalize(terrain_normal).y, 0.0, 1.0);
	float patch = sin(terrain_position.x * 0.012 + sin(terrain_position.z * 0.008))
		* sin(terrain_position.z * 0.016 + terrain_position.x * 0.003) * 0.5 + 0.5;
	vec3 grass = mix(vec3(0.32, 0.39, 0.25), vec3(0.42, 0.44, 0.29), patch * 0.65);
	vec3 base = mix(vec3(0.48, 0.43, 0.29), grass, smoothstep(0.0, 5.5, h));
	vec3 rock = mix(vec3(0.39, 0.40, 0.36), vec3(0.54, 0.51, 0.43), patch);
	base = mix(base, rock, smoothstep(0.09, 0.38, slope));
	base = mix(base, rock, smoothstep(60.0, 110.0, h) * 0.5);
	// Sparse, anti-aliased contours retain altitude cues without black terraces.
	float height_line = abs(fract(h / 20.0 - 0.5) - 0.5) * 20.0;
	float contour = 1.0 - smoothstep(0.12, max(0.3, fwidth(h) * 1.3), height_line);
	ALBEDO = base * 0.68 * (1.0 - contour * smoothstep(12.0, 25.0, h) * 0.12);
	ROUGHNESS = 0.94;
}
