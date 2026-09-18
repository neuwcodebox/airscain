shader_type spatial;
render_mode diffuse_burley;

#include "res://world/sky_atmosphere.gdshaderinc"

uniform sampler2D terrain_heights : filter_linear, repeat_disable;
uniform float battlefield_size = 2400.0;
varying vec2 water_position;

float swell(vec2 p) {
	float broad = sin(dot(p, vec2(0.011, 0.004)) + TIME * 0.42);
	float crossing = sin(dot(p, vec2(-0.006, 0.016)) - TIME * 0.31 + broad * 0.35);
	float detail = sin(dot(p, vec2(0.027, -0.019)) + TIME * 0.67 + crossing * 0.22);
	return broad * 0.46 + crossing * 0.34 + detail * 0.20;
}

void vertex() {
	water_position = VERTEX.xz;
}

void fragment() {
	vec2 map_uv = water_position / battlefield_size + 0.5;
	float height = texture(terrain_heights, clamp(map_uv, vec2(0.0), vec2(1.0))).r;
	float depth = max(-height, 0.0);
	float shallow = 1.0 - smoothstep(1.0, 24.0, depth);
	vec2 p = water_position;
	float wave = swell(p);
	vec3 water = mix(vec3(0.045, 0.19, 0.25), vec3(0.16, 0.38, 0.37), shallow);
	float foam = (1.0 - smoothstep(0.5, 3.5, depth)) * smoothstep(0.34, 0.82, wave);
	ALBEDO = mix(water + wave * 0.018, vec3(0.65, 0.75, 0.66), foam * 0.55);
	vec2 slope = vec2(swell(p + vec2(2.0, 0.0)), swell(p + vec2(0.0, 2.0))) - vec2(wave);
	NORMAL_MAP = normalize(vec3(-slope * 0.55, 1.0)) * 0.5 + 0.5;
	ROUGHNESS = 0.72;
	SPECULAR = 0.09;
	// Only the far sea receives aerial haze; keep the playable coast unchanged.
	float haze = smoothstep(battlefield_size * 0.85, battlefield_size * 2.2, length(water_position));
	vec3 ray = normalize((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD);
	ALBEDO *= 1.0 - haze;
	EMISSION = atmosphere(ray) * haze;
	SPECULAR *= 1.0 - haze;
}
