shader_type spatial;
render_mode diffuse_burley;

varying vec3 terrain_position;
varying vec3 terrain_normal;
uniform bool placement_contours = false;
uniform vec3 placement_center = vec3(0.0);

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
	vec3 soil = mix(vec3(0.38, 0.32, 0.23), rock, smoothstep(0.025, 0.12, slope));
	base = mix(base, soil, smoothstep(0.008, 0.10, slope) * 0.78);
	base = mix(base, rock, smoothstep(60.0, 110.0, h) * 0.5);
	// Broad slope contrast, with no extra geometry or texture samples.
	base *= 1.0 - smoothstep(0.002, 0.10, slope) * 0.16;
	float interval = 20.0;
	float height_line = abs(fract(h / interval - 0.5) - 0.5) * interval;
	float footprint = max(fwidth(h), 0.001);
	float contour = 1.0 - smoothstep(0.10, max(0.25, footprint * 1.3), height_line);
	float local_weight = placement_contours ? 1.0 - smoothstep(130.0, 240.0, distance(terrain_position.xz, placement_center.xz)) : 0.0;
	float detail_line = abs(fract(h / 10.0 - 0.5) - 0.5) * 10.0;
	float detail_contour = 1.0 - smoothstep(0.10, max(0.25, footprint * 1.3), detail_line);
	contour = mix(contour, detail_contour, local_weight);
	// Fade subpixel contours and keep level plateaus free of painted bands.
	contour *= smoothstep(0.0003, 0.003, slope) * (1.0 - smoothstep(2.0, 5.0, footprint));
	ALBEDO = base * 0.68 * (1.0 - contour * mix(0.07, 0.28, local_weight));
	ROUGHNESS = 0.94;
}
