shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D core_texture : source_color;
uniform float batch_time = 0.0;

varying float fire_age;
varying float outer_layer;
varying float fire_seed;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

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
	float elapsed = batch_time - INSTANCE_CUSTOM.x;
	outer_layer = INSTANCE_CUSTOM.w;
	float duration = mix(0.9, 1.3, outer_layer);
	fire_age = elapsed / duration;
	fire_seed = INSTANCE_CUSTOM.y;
	float azimuth = hash11(fire_seed * 1.71) * 6.283185;
	float vertical = mix(-0.34, 0.92, hash11(fire_seed * 3.13));
	vec3 direction = normalize(vec3(cos(azimuth), vertical, sin(azimuth)));
	float speed = mix(2.5, 11.0, hash11(fire_seed * 5.37));
	float damping = mix(4.0, 8.0, outer_layer);
	float travel = speed * (1.0 - exp(-damping * elapsed)) / damping;
	vec3 offset = direction * travel;
	offset.y += mix(0.5, 2.2, outer_layer) * elapsed * elapsed * 0.5;
	float initial_radius = mix(2.4, 2.2, outer_layer) * pow(hash11(fire_seed * 7.91), 0.333);
	offset += direction * initial_radius;
	float growth = outer_layer > 0.5
		? mix(0.35, 1.5, smoothstep(0.0, 0.25, fire_age))
		: mix(0.25, 1.15, smoothstep(0.0, 0.18, fire_age)) * mix(1.0, 0.18, smoothstep(0.55, 1.0, fire_age));
	float random_scale = mix(1.5, 3.8, hash11(fire_seed * 11.17));
	random_scale *= mix(0.72, 1.0, outer_layer);
	float active = step(0.0, elapsed) * (1.0 - step(1.0, fire_age));
	float size = growth * random_scale * INSTANCE_CUSTOM.z * active;
	VERTEX.xy *= size;
	mat4 facing = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	facing[3].xyz += offset;
	MODELVIEW_MATRIX = VIEW_MATRIX * facing;
}

void fragment() {
	if (fire_age < 0.0 || fire_age >= 1.0) {
		discard;
	}
	vec2 centered = UV - 0.5;
	float n = value_noise(UV * 3.2 + fire_seed) * 0.6 + value_noise(UV * 7.0 - fire_seed) * 0.4;
	float shape = 1.0 - length(centered) * 2.0 + (n - 0.5) * 0.9;
	float core_mask = texture(core_texture, UV).a * smoothstep(mix(-0.08, 0.34, fire_age), mix(0.14, 0.56, fire_age), shape);
	float outer_mask = smoothstep(mix(0.02, 0.55, fire_age), mix(0.24, 0.77, fire_age), shape);
	float mask = mix(core_mask, outer_mask, outer_layer);
	vec3 core_fire = mix(COLOR.rgb, vec3(1.0, 0.88, 0.58), 0.3);
	vec3 hot_body = mix(vec3(1.0, 0.8, 0.45), COLOR.rgb, 0.35);
	vec3 warm_body = mix(vec3(1.0, 0.42, 0.1), COLOR.rgb, 0.3);
	vec3 cool_body = mix(vec3(0.17, 0.12, 0.1), COLOR.rgb * 0.18, 0.25);
	vec3 body_fire = mix(hot_body, warm_body, smoothstep(0.04, 0.36, fire_age));
	body_fire = mix(body_fire, cool_body, smoothstep(0.68, 1.0, fire_age));
	vec3 fire = mix(core_fire, body_fire, outer_layer) * mix(0.72, 1.2, n);
	float core_fade = smoothstep(0.0, 0.08, fire_age) * (1.0 - smoothstep(0.78, 1.0, fire_age));
	float body_fade = smoothstep(0.0, 0.05, fire_age) * (1.0 - smoothstep(0.66, 1.0, fire_age));
	float fade = mix(core_fade, body_fade, outer_layer);
	ALBEDO = fire;
	EMISSION = fire * mix(mix(6.0, 1.8, fire_age), mix(2.2, 0.25, smoothstep(0.45, 1.0, fire_age)), outer_layer);
	ALPHA = mask * fade;
}
