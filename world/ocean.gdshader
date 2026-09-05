shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D terrain_heights : filter_linear, repeat_disable;
uniform float battlefield_size = 2400.0;
varying vec2 water_position;

float hash_water(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float water_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash_water(cell), hash_water(cell + vec2(1.0, 0.0)), u.x),
		mix(hash_water(cell + vec2(0.0, 1.0)), hash_water(cell + vec2(1.0)), u.x), u.y);
}

float swell(vec2 p) {
	vec2 drift = vec2(TIME * 0.025, -TIME * 0.013);
	float broad = water_noise(p * 0.009 + drift);
	vec2 rotated = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p;
	return broad * 0.72 + water_noise(rotated * 0.023 + vec2(broad * 1.7) - drift) * 0.28;
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
	float foam = (1.0 - smoothstep(0.5, 3.5, depth)) * smoothstep(0.22, 0.7, wave);
	ALBEDO = mix(water + (wave - 0.5) * 0.025, vec3(0.65, 0.75, 0.66), foam * 0.6);
	vec2 slope = vec2(swell(p + vec2(3.0, 0.0)), swell(p + vec2(0.0, 3.0))) - vec2(wave);
	NORMAL_MAP = normalize(vec3(-slope * 0.22, 1.0)) * 0.5 + 0.5;
	ROUGHNESS = 0.68;
	SPECULAR = 0.12;
}
