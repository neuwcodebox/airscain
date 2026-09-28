shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D card : source_color;
uniform vec3 tint : source_color = vec3(1.0, 0.55, 0.23);
varying float age;
varying float variation;
varying flat uint camera_layers;

void vertex() {
	age = INSTANCE_CUSTOM.y;
	camera_layers = CAMERA_VISIBLE_LAYERS;
	variation = fract(float(INSTANCE_ID) * 0.6180339);
	// Rotate each card in camera space while keeping its particle scale.
	float spin = INSTANCE_CUSTOM.x;
	mat4 facing = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	facing = facing * mat4(vec4(cos(spin), -sin(spin), 0.0, 0.0), vec4(sin(spin), cos(spin), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	facing = facing * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * facing;
}

void fragment() {
	if (camera_layers == uint(524288)) { discard; }
	vec2 p = UV - 0.5;
	float angle = atan(p.y, p.x);
	float distortion = 1.0 + 0.05 * sin(angle * 5.0 + variation * 6.28 + age * 2.0) + 0.025 * sin(angle * 9.0 - variation * 9.0);
	vec2 sample_uv = p * distortion + 0.5;
	float density = texture(card, sample_uv).a;
	float edge = smoothstep(0.0, 0.45, density);
	float heat = pow(1.0 - age, 5.0);
	float inner = smoothstep(0.18, 0.65, density);
	ALBEDO = mix(vec3(0.19, 0.18, 0.17), tint * (0.5 + density * 0.55), heat * inner);
	EMISSION = tint * heat * inner * (1.1 + variation * 0.6);
	ALPHA = edge * COLOR.a * (0.55 + density * 0.42);
}
