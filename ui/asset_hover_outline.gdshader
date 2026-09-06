shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 normal = MODELVIEW_NORMAL_MATRIX * NORMAL;
	vec2 direction = (PROJECTION_MATRIX * vec4(normal, 0.0)).xy;
	float length_squared = dot(direction, direction);
	if (length_squared > 0.00001) {
		clip.xy += direction * inversesqrt(length_squared) * (2.0 * 2.0 / VIEWPORT_SIZE) * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = vec3(0.32, 0.88, 1.0);
}
