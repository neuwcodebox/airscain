// Shared by the sky and the distant sea, so the finite water plane has no rim.
uniform vec3 sun_direction = vec3(0.0, 0.6, 0.8);
uniform vec4 zenith_color : source_color = vec4(0.18, 0.36, 0.58, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.66, 0.78, 0.83, 1.0);
uniform float daylight = 1.0;
uniform float twilight = 0.0;

vec3 atmosphere(vec3 ray) {
	float altitude = max(ray.y, 0.0);
	vec3 base = mix(horizon_color.rgb, zenith_color.rgb, pow(clamp(altitude, 0.0, 1.0), 0.38));
	float facing = clamp(dot(normalize(vec3(ray.x, 0.001, ray.z)), normalize(vec3(sun_direction.x, 0.001, sun_direction.z))), -1.0, 1.0);
	float horizon_band = exp(-altitude * 7.0);
	base += vec3(0.55, 0.19, 0.035) * twilight * pow(max(facing, 0.0), 5.0) * horizon_band;
	// A quieter anti-solar rose band keeps sunset from tinting the entire dome orange.
	base += vec3(0.065, 0.023, 0.046) * twilight * (1.0 - facing) * exp(-pow((altitude - 0.09) * 7.0, 2.0));
	base += vec3(0.16, 0.14, 0.10) * daylight * pow(max(dot(ray, sun_direction), 0.0), 12.0);
	return base;
}
