uniform float trail_time = 0.0;
uniform float trail_lifetime = 16.0;
uniform float trail_initial_scale = 1.0;
uniform float trail_final_scale = 3.5;
uniform float trail_drift_speed = 0.18;

vec4 trail_motion(vec4 data, vec3 encoded_drift) {
	float age = max(0.0, trail_time - data.x);
	float t = clamp(age / trail_lifetime, 0.0, 1.0);
	float scale = mix(trail_initial_scale, trail_final_scale, smoothstep(0.0, 1.0, t)) * data.y;
	return vec4((encoded_drift - vec3(0.5)) * 4.0 * trail_drift_speed * age, scale);
}

float trail_alpha(vec4 data) {
	float t = clamp((trail_time - data.x) / trail_lifetime, 0.0, 1.0);
	return smoothstep(0.0, 0.015, t) * (1.0 - smoothstep(0.45, 0.88, t)) * data.z;
}
