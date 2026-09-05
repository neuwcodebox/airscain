shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D terrain_heights : filter_linear, repeat_disable;
uniform float battlefield_size = 2400.0;
varying vec2 water_position;

void vertex() {
	water_position = VERTEX.xz;
}

void fragment() {
	vec2 map_uv = water_position / battlefield_size + 0.5;
	float height = texture(terrain_heights, clamp(map_uv, vec2(0.0), vec2(1.0))).r;
	float depth = max(-height, 0.0);
	float shallow = 1.0 - smoothstep(1.0, 24.0, depth);
	vec2 p = water_position;
	float wave = sin(p.x * 0.075 + p.y * 0.038 + sin(p.y * 0.016) * 2.0 + TIME * 0.7);
	float crossing = sin(p.x * -0.025 + p.y * 0.092 + sin(p.x * 0.021) * 1.7 - TIME * 0.45);
	vec3 water = mix(vec3(0.045, 0.19, 0.25), vec3(0.16, 0.38, 0.37), shallow);
	float foam = (1.0 - smoothstep(0.5, 3.5, depth)) * smoothstep(-0.4, 0.5, wave + crossing * 0.3);
	ALBEDO = mix(water + (wave + crossing) * 0.006, vec3(0.65, 0.75, 0.66), foam * 0.6);
	NORMAL_MAP = normalize(vec3(wave * 0.025, crossing * 0.025, 1.0)) * 0.5 + 0.5;
	ROUGHNESS = 0.58;
	SPECULAR = 0.16;
}
