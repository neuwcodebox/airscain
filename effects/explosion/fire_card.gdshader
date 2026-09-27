shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Billowing fire cards: particle color carries the temperature ramp; noise erodes
// each card with age so the fireball breaks up into ragged, cooling tongues.
uniform vec3 tint : source_color = vec3(1.0);
uniform float heat = 1.3;

varying float age;
varying float seed;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	age = INSTANCE_CUSTOM.y;
	seed = hash21(vec2(float(INSTANCE_ID), 7.0)) * 40.0;
	// Camera-facing card that keeps the particle's scale and spin.
	mat4 facing = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float spin = INSTANCE_CUSTOM.x;
	facing = facing * mat4(vec4(cos(spin), -sin(spin), 0.0, 0.0), vec4(sin(spin), cos(spin), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	facing = facing * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * facing;
}

void fragment() {
	vec2 centered = UV - 0.5;
	float n = value_noise(UV * 3.2 + seed) * 0.6 + value_noise(UV * 7.0 - seed) * 0.4;
	float shape = 1.0 - length(centered) * 2.0 + (n - 0.5) * 0.9;
	float erosion = mix(0.02, 0.55, age);
	float mask = smoothstep(erosion, erosion + 0.22, shape);
	float glow = heat * (1.0 - smoothstep(0.0, 0.3, age)) * (0.75 + n * 0.5);
	// Darker, cooler rims and noisy interior give each card some volume.
	float body = mix(0.55, 1.15, n) * mix(0.7, 1.0, smoothstep(0.0, 0.5, shape));
	ALBEDO = COLOR.rgb * tint * body * (1.0 + glow);
	ALPHA = mask * COLOR.a;
}
