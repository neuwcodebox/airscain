shader_type sky;

#include "res://world/sky_atmosphere.gdshaderinc"

uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 moon_direction = vec3(0.0, 1.0, 0.0);
uniform float night_amount = 0.0;
uniform float sky_clock = 0.0;
uniform float star_rotation = 0.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 starlight(vec3 ray) {
	float longitude = atan(ray.z, ray.x) + star_rotation;
	vec2 field = vec2(fract(longitude / TAU + 0.5), asin(clamp(ray.y, -1.0, 1.0)) / PI + 0.5) * vec2(420.0, 210.0);
	vec2 cell = floor(field);
	float seed = hash21(cell);
	float selection = step(1.0 - 0.018 * sqrt(max(0.0, 1.0 - ray.y * ray.y)), seed);
	vec2 point = vec2(hash21(cell + 7.3), hash21(cell + 19.1)) * 0.65 + 0.175;
	float radius = mix(0.035, 0.10, hash21(cell + 31.0));
	float aa = max(length(fwidth(field)) * 0.45, 0.012);
	float star = 1.0 - smoothstep(radius, radius + aa, length(fract(field) - point));
	vec3 tint = mix(vec3(0.64, 0.78, 1.0), vec3(1.0, 0.88, 0.66), hash21(cell + 47.0));
	return tint * star * selection * (0.85 + 0.15 * sin(sky_clock * 0.32 + seed * 400.0));
}

vec3 moonlight(vec3 ray) {
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), moon_direction));
	vec3 up = cross(moon_direction, right);
	vec2 disk = vec2(dot(ray, right), dot(ray, up)) / 0.013;
	float radius = length(disk);
	float aa = max(fwidth(radius), 0.001);
	float mask = (1.0 - smoothstep(1.0 - aa, 1.0 + aa, radius)) * step(0.0, dot(ray, moon_direction));
	vec3 normal = vec3(disk, sqrt(max(0.0, 1.0 - dot(disk, disk))));
	float phase = smoothstep(-0.05, 0.18, dot(normal, normalize(vec3(-0.55, 0.2, 0.8))));
	float relief = texture(cloud_noise, disk * 0.18 + vec2(0.31, 0.73)).r;
	vec3 body = vec3(0.65, 0.72, 0.83) * (0.67 + relief * 0.4) * mix(0.035, 1.0, phase) * mask;
	float halo = exp(-max(0.0, 1.0 - dot(ray, moon_direction)) * 900.0);
	return body + vec3(0.016, 0.026, 0.048) * halo;
}

void sky() {
	vec3 ray = normalize(EYEDIR);
	vec3 color = atmosphere(ray);
	// Small real-time reflection map: keep only the broad atmospheric illumination.
	if (!AT_CUBEMAP_PASS) {
		float horizon_mask = smoothstep(-0.015, 0.065, ray.y);
		float sun_distance = length(ray - sun_direction);
		float sun_aa = max(fwidth(sun_distance), 0.00015);
		float disk = 1.0 - smoothstep(0.009 - sun_aa, 0.009 + sun_aa, sun_distance);
		vec3 sunlight = mix(vec3(1.0, 0.39, 0.10), vec3(1.0, 0.91, 0.68), daylight);
		color += sunlight * (disk * 2.5 + exp(-sun_distance * 42.0) * 0.32) * smoothstep(-0.04, 0.01, sun_direction.y);
		if (night_amount > 0.001) {
			color += starlight(ray) * night_amount * horizon_mask * 0.65;
			color += moonlight(ray) * night_amount * horizon_mask;
		}
		// Curved cloud deck: bounded projection avoids an infinitely dense horizon.
		vec2 uv = ray.xz / (max(ray.y, 0.0) + 0.16) * 0.19;
		vec2 wind = vec2(0.00055, 0.00016) * sky_clock;
		float broad = texture(cloud_noise, uv + wind).r;
		float detail = texture(cloud_noise, uv * 3.1 - wind * 0.47).r;
		float density = broad * 0.79 + detail * 0.21;
		float coverage = smoothstep(0.46, 0.63, density) * horizon_mask;
		float shoulder = texture(cloud_noise, uv + wind + sun_direction.xz * 0.035).r;
		float illumination = clamp(0.5 + (shoulder - broad) * 3.0 + (density - 0.5) * 1.5, 0.0, 1.0);
		vec3 shade = mix(vec3(0.018, 0.028, 0.052), vec3(0.27, 0.37, 0.48), daylight);
		vec3 crown = mix(vec3(0.052, 0.072, 0.11), vec3(0.88, 0.89, 0.82), daylight);
		float sun_facing = pow(max(dot(ray, sun_direction), 0.0), 3.0);
		crown += vec3(0.7, 0.23, 0.045) * twilight * sun_facing;
		vec3 cloud = mix(shade, crown, illumination);
		float moon_facing = pow(max(dot(ray, moon_direction), 0.0), 24.0);
		cloud += vec3(0.07, 0.10, 0.16) * moon_facing * night_amount * (0.35 + illumination);
		cloud += sunlight * pow(max(dot(ray, sun_direction), 0.0), 16.0) * pow(1.0 - coverage, 3.0) * daylight * 0.55;
		// Distant cloud banks dissolve into the same horizon haze as the sea.
		cloud = mix(atmosphere(ray), cloud, smoothstep(0.0, 0.16, ray.y));
		color = mix(color, cloud, coverage * mix(0.84, 0.96, daylight));
	}
	COLOR = max(color, vec3(0.0));
}
