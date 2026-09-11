uniform float trail_time = 0.0;
uniform float trail_lifetime = 16.0;
uniform float trail_fade_end = 0.88;
uniform float trail_initial_scale = 1.0;
uniform float trail_final_scale = 3.5;
uniform float trail_drift_speed = 0.18;
uniform float trail_turbulence_strength = 0.0;

vec4 trail_motion(vec4 data, vec3 encoded_drift, vec3 origin) {
	float age = max(0.0, trail_time - data.x);
	float t = clamp(age / trail_lifetime, 0.0, 1.0);
	float scale = mix(trail_initial_scale, trail_final_scale, smoothstep(0.0, 1.0, t)) * data.y;
	vec3 drift = (encoded_drift - vec3(0.5)) * 4.0 * trail_drift_speed * age;
	if (trail_turbulence_strength > 0.0) {
		// Neighboring puffs share a smoothly warped field, not independent jitter.
		// Bounded displacement: time changes phase, never speed or travel radius.
		vec3 q = origin * 0.18;
		float phase = trail_time * 0.22;
		vec3 warp = sin(q.zxy * 0.73 + vec3(phase * 0.7, -phase * 0.6, phase * 0.5));
		vec3 large = sin(vec3(dot(q, vec3(0.8, 0.4, 1.1)), dot(q, vec3(-0.7, 1.0, 0.5)), dot(q, vec3(1.0, -0.6, 0.3))) + warp + vec3(phase, -phase * 0.8, phase * 0.6));
		vec3 small = sin(q.yzx * 2.3 + warp * 1.2 + vec3(-phase * 1.1, phase * 0.9, phase));
		float growth = smoothstep(0.4, 6.0, age);
		drift += (large + small * 0.28) * trail_turbulence_strength * growth;
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
