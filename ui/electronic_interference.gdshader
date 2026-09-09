shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled;

uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float angle = atan(p.y, p.x);
	float drift = TIME * 1.8;
	float warp = sin(angle * 7.0 + drift) * 0.025 + sin(angle * 13.0 - drift * 0.6) * 0.015;
	float wave = sin((radius + warp) * 34.0 - drift * 2.0);
	float arcs = smoothstep(0.55, 0.9, wave);
	float breaks = smoothstep(-0.65, 0.3, sin(angle * 9.0 + radius * 11.0 + drift * 0.3));
	float boundary = (1.0 - smoothstep(0.65, 1.0, radius)) * smoothstep(0.1, 0.25, radius);
	float grain = sin(p.x * 91.0 + p.y * 113.0 + floor(TIME * 12.0)) * 0.5 + 0.5;
	float intensity = mix(0.35, 1.0, strength);
	ALBEDO = mix(vec3(0.48, 0.12, 0.8), vec3(1.0, 0.28, 0.94), arcs);
	ALPHA = boundary * intensity * (0.12 + grain * 0.08 + arcs * breaks * 0.68);
}
