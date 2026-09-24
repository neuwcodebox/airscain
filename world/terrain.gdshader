shader_type spatial;
render_mode diffuse_burley;
#include "res://effects/smoke_shadow_sampling.gdshaderinc"
#include "res://effects/placement_surface_light.gdshaderinc"
varying vec3 shadow_receiver_position;

varying vec3 terrain_position;
varying vec3 terrain_normal;
uniform bool placement_contours = false;
uniform vec3 placement_center = vec3(0.0);
uniform bool radar_coverage_enabled = false;
uniform sampler2D radar_coverage_map : filter_linear, repeat_disable;
uniform float battlefield_size = 2400.0;
// R forest, G dry grass, B farmland, A curvature (0.5 flat); see GroundCover.
uniform sampler2D ground_cover_map : filter_linear, repeat_disable, hint_default_black;
uniform float field_rotation = 0.0;
uniform float sea_level = 0.0;

const vec3 LUSH = vec3(0.155, 0.235, 0.085);
const vec3 MEADOW = vec3(0.255, 0.300, 0.125);
const vec3 DRY = vec3(0.400, 0.360, 0.190);
const vec3 FOREST_FLOOR = vec3(0.075, 0.120, 0.055);
const vec3 SOIL = vec3(0.270, 0.205, 0.135);
const vec3 ROCK_DARK = vec3(0.250, 0.245, 0.225);
const vec3 ROCK_LIGHT = vec3(0.430, 0.410, 0.360);
const vec3 SAND = vec3(0.610, 0.540, 0.380);
const vec3 WET_SAND = vec3(0.330, 0.290, 0.210);

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

mat2 field_basis() {
	return mat2(vec2(cos(field_rotation), sin(field_rotation)), vec2(-sin(field_rotation), cos(field_rotation)));
}

// Whole fields: each rectangular cell is farmed or not from the cover map at its center.
vec4 field_color(vec2 world_xz, float footprint) {
	vec2 cell_size = vec2(96.0, 58.0);
	vec2 local = field_basis() * world_xz;
	vec2 cell = floor(local / cell_size);
	vec2 inside = fract(local / cell_size);
	vec2 center = transpose(field_basis()) * ((cell + 0.5) * cell_size);
	float farmed = step(0.3, texture(ground_cover_map, center / battlefield_size + vec2(0.5)).b);
	float pick = hash21(cell + 17.0);
	vec3 crop = pick < 0.28 ? vec3(0.430, 0.360, 0.160) : pick < 0.58 ? vec3(0.170, 0.250, 0.075) : pick < 0.78 ? vec3(0.240, 0.180, 0.115) : vec3(0.280, 0.285, 0.140);
	crop *= 0.9 + hash21(cell + 3.0) * 0.2;
	// Plough rows along the long side; fade them before they alias.
	float rows = sin(local.y * 2.4 + pick * 20.0) * 0.5 + 0.5;
	crop *= 1.0 - rows * 0.12 * (1.0 - smoothstep(0.4, 1.4, footprint));
	// Hedgerows and tracks between fields.
	vec2 edge = min(inside, 1.0 - inside) * cell_size;
	float hedge = 1.0 - smoothstep(1.2, 1.2 + footprint * 1.5 + 0.8, min(edge.x, edge.y));
	return vec4(mix(crop, vec3(0.110, 0.160, 0.070), hedge * 0.85), farmed);
}

void vertex() {
	shadow_receiver_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	terrain_position = VERTEX;
	terrain_normal = NORMAL;
}

void fragment() {
	float h = terrain_position.y;
	vec2 p = terrain_position.xz;
	float slope = 1.0 - clamp(normalize(terrain_normal).y, 0.0, 1.0);
	float footprint_xz = max(length(fwidth(p)), 0.001);
	vec4 cover = texture(ground_cover_map, p / battlefield_size + vec2(0.5));
	float bend = cover.a * 2.0 - 1.0;
	float macro = value_noise(p / 190.0);
	float mid = value_noise(p / 37.0 + 11.0);
	float fine_fade = 1.0 - smoothstep(1.5, 5.0, footprint_xz);
	float fine = mix(0.5, value_noise(p / 6.5 - 5.0), fine_fade);

	vec3 grass = mix(LUSH, MEADOW, clamp(mid * 0.8 + macro * 0.4 - 0.1, 0.0, 1.0));
	float dry = clamp(cover.g * 0.85 + (macro - 0.5) * 0.35 - bend * 0.25, 0.0, 1.0);
	grass = mix(grass, DRY, smoothstep(0.45, 0.95, dry) * 0.8);
	vec3 base = mix(grass, FOREST_FLOOR * (0.85 + mid * 0.3), smoothstep(0.08, 0.55, cover.r));
	vec4 field = field_color(p, footprint_xz);
	base = mix(base, field.rgb, field.a);
	// Hollows collect moisture; exposed ridges are paler.
	base *= 1.0 + clamp(-bend, 0.0, 1.0) * 0.18 - clamp(bend, 0.0, 1.0) * 0.12;

	float strata = sin(h * 0.9 + mid * 4.0) * 0.5 + 0.5;
	vec3 rock = mix(ROCK_DARK, ROCK_LIGHT, strata * 0.6 + fine * 0.4);
	vec3 soil = mix(SOIL, rock, smoothstep(0.10, 0.22, slope));
	base = mix(base, soil, smoothstep(0.035 + mid * 0.03, 0.13, slope));
	base = mix(base, rock, smoothstep(55.0, 95.0, h + mid * 20.0) * 0.45);

	float shore = sea_level + 2.6 + (mid - 0.5) * 2.4;
	vec3 sand = mix(WET_SAND, SAND, smoothstep(sea_level - 0.4, sea_level + 1.1, h));
	base = mix(base, sand, 1.0 - smoothstep(shore - 0.8, shore + 0.8, h));
	base *= 0.88 + fine * 0.24;

	float interval = 20.0;
	float height_line = abs(fract(h / interval - 0.5) - 0.5) * interval;
	float footprint = max(fwidth(h), 0.001);
	float contour = 1.0 - smoothstep(0.10, max(0.25, footprint * 1.3), height_line);
	float local_weight = placement_contours ? 1.0 - smoothstep(130.0, 240.0, distance(terrain_position.xz, placement_center.xz)) : 0.0;
	float detail_line = abs(fract(h / 10.0 - 0.5) - 0.5) * 10.0;
	float detail_contour = 1.0 - smoothstep(0.10, max(0.25, footprint * 1.3), detail_line);
	contour = mix(contour, detail_contour, local_weight);
	// Fade subpixel contours and keep level plateaus free of painted bands.
	contour *= smoothstep(0.0003, 0.003, slope) * (1.0 - smoothstep(2.0, 5.0, footprint));
	ALBEDO = base * (1.0 - contour * mix(0.05, 0.28, local_weight));
	if (radar_coverage_enabled) {
		vec2 coverage_uv = terrain_position.xz / battlefield_size + vec2(0.5);
		vec4 coverage = texture(radar_coverage_map, clamp(coverage_uv, vec2(0.0), vec2(1.0)));
		ALBEDO = mix(ALBEDO, coverage.rgb, coverage.a);
	}
	// Gentle relief from the mid-scale noise; fades out where it would shimmer.
	float relief_fade = 1.0 - smoothstep(2.0, 6.0, footprint_xz);
	vec2 step_xz = vec2(1.6, 0.0);
	float gx = value_noise((p + step_xz.xy) / 9.0) - value_noise((p - step_xz.xy) / 9.0);
	float gz = value_noise((p + step_xz.yx) / 9.0) - value_noise((p - step_xz.yx) / 9.0);
	vec3 world_bump = vec3(-gx, 0.0, -gz) * 0.55 * relief_fade;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(world_bump, 0.0)).xyz);
	ROUGHNESS = 0.94;
	ALBEDO *= 1.0 - projected_smoke_shadow(shadow_receiver_position);
	EMISSION = placement_surface_light(shadow_receiver_position, ALBEDO);
}
