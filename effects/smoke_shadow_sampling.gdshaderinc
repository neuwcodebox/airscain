uniform sampler2D smoke_shadow_map : filter_nearest, repeat_disable;
uniform mat4 smoke_shadow_projection;
uniform float smoke_shadow_strength = 0.0;

float projected_smoke_shadow(vec3 world_position) {
	if (smoke_shadow_strength <= 0.0) { return 0.0; }
	vec4 clip = smoke_shadow_projection * vec4(world_position, 1.0);
	vec3 projected = clip.xyz / clip.w * 0.5 + 0.5;
	vec2 uv = vec2(projected.x, 1.0 - projected.y);
	if (any(lessThan(uv, vec2(0.002))) || any(greaterThan(uv, vec2(0.998)))) { return 0.0; }
	float covered = 0.0;
	vec2 dimensions = vec2(textureSize(smoke_shadow_map, 0));
	vec2 pixel = uv * dimensions - 0.5;
	vec2 fraction = fract(pixel);
	for (int y = 0; y <= 1; y++) {
		for (int x = 0; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec3 sample_depth = texture(smoke_shadow_map, (floor(pixel) + offset + 0.5) / dimensions).rgb;
			float depth = dot(sample_depth, vec3(1.0, 1.0 / 255.0, 1.0 / 65025.0));
			vec2 weight = mix(vec2(1.0) - fraction, fraction, offset);
			covered += step(depth + 0.0005, projected.z) * weight.x * weight.y;
		}
	}
	return covered * smoke_shadow_strength;
}
