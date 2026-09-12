uniform float trail_time = 0.0;
uniform float trail_lifetime = 16.0;
uniform float trail_fade_end = 0.88;
uniform float trail_initial_scale = 1.0;
uniform float trail_final_scale = 3.5;
uniform float trail_drift_speed = 0.18;
uniform float trail_turbulence_strength = 0.0;

float trail_hash11(float value) {
	value = fract(value * 0.1031);
	value *= value + 33.33;
	value *= value + value;
	return fract(value);
}

float trail_value_noise(float point) {
	float cell = floor(point);
	float local = fract(point);
	float blend = local * local * (3.0 - 2.0 * local);
	return mix(trail_hash11(cell), trail_hash11(cell + 1.0), blend) * 2.0 - 1.0;
}

vec4 trail_motion(vec4 data, vec3 encoded_drift, vec3 origin) {
	float age = max(0.0, trail_time - data.x);
	float t = clamp(age / trail_lifetime, 0.0, 1.0);
	float scale = mix(trail_initial_scale, trail_final_scale, smoothstep(0.0, 1.0, t)) * data.y;
	vec3 drift = (encoded_drift - vec3(0.5)) * 4.0 * trail_drift_speed * age;
	if (trail_turbulence_strength > 0.0) {
		// Neighboring puffs share a continuous aperiodic field instead of a repeating wave.
		// Diffusion keeps growing through fade-out; slower advection prevents rising travel speed.
		float phase = data.x * 0.22 + 0.88 * log(1.0 + age * 0.25);
		float warp = trail_value_noise(dot(origin, vec3(0.009, -0.011, 0.013)) + phase * 0.17);
		vec3 large = vec3(
			trail_value_noise(dot(origin, vec3(0.019, 0.011, -0.015)) + phase * 0.31 + warp * 0.73),
			trail_value_noise(dot(origin, vec3(-0.017, 0.023, 0.013)) - phase * 0.23 - warp * 0.57 + 17.0),
			trail_value_noise(dot(origin, vec3(0.013, -0.018, 0.021)) + phase * 0.19 + warp * 0.49 + 41.0)
		);
		vec3 small = vec3(
			trail_value_noise(dot(origin, vec3(0.061, -0.037, 0.049)) - phase * 0.67 - warp * 1.17 + 73.0),
			trail_value_noise(dot(origin, vec3(-0.053, 0.071, 0.043)) + phase * 0.59 + warp * 0.91 + 101.0),
			trail_value_noise(dot(origin, vec3(0.047, 0.039, -0.067)) - phase * 0.53 - warp * 1.03 + 149.0)
		);
		float growth = sqrt(1.0 + age * 0.5) - 1.0;
		drift += (large * 2.4 + small * 1.2) * trail_turbulence_strength * growth;
	}
	return vec4(drift, scale);
}

float trail_alpha(vec4 data) {
	float t = clamp((trail_time - data.x) / trail_lifetime, 0.0, 1.0);
	return smoothstep(0.0, 0.015, t) * (1.0 - smoothstep(0.45, trail_fade_end, t)) * data.z;
}

// World-radius haze survives detaching a trail from its aircraft.
uniform float haze_start_radius = 0.0;
uniform float haze_end_radius = 0.0;
float trail_haze(vec3 world_position) {
	return haze_end_radius > haze_start_radius ? 1.0 - smoothstep(haze_start_radius, haze_end_radius, length(world_position.xz)) : 1.0;
}
