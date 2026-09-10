shader_type spatial;
render_mode cull_disabled, unshaded, fog_disabled;

#include "res://effects/trail_motion.gdshaderinc"
uniform bool trail_enabled = false;
uniform float shadow_radius = 1.0;
uniform float opacity_ratio : hint_range(0.0, 1.0) = 1.0;

varying flat uint camera_layers;
varying flat float sphere_visible;
varying flat vec3 sphere_ray;
varying vec3 sphere_origin;
varying vec3 sphere_plane;

void vertex() {
	camera_layers = CAMERA_VISIBLE_LAYERS;
	float alpha = trail_enabled ? trail_alpha(INSTANCE_CUSTOM) : COLOR.a;
	float radius = shadow_radius * sqrt(max(smoothstep(0.02, 0.35, alpha) * opacity_ratio, 0.0));
	vec3 drift = vec3(0.0);
	if (trail_enabled) {
		vec4 motion = trail_motion(INSTANCE_CUSTOM, COLOR.rgb);
		drift = motion.xyz;
		radius *= motion.w * trail_haze(MODEL_MATRIX[3].xyz + drift);
	}
	mat3 axes = mat3(MODELVIEW_MATRIX);
	sphere_visible = 0.0;
	sphere_ray = vec3(0.0, 0.0, 1.0);
	sphere_origin = vec3(0.0);
	sphere_plane = vec3(0.0);
	POSITION = vec4(0.0, 0.0, 0.0, 1.0);
	if (radius > 0.000001 && abs(determinant(axes)) > 0.000000000001) {
		// Orthographic light camera: project an ellipsoid's bounds onto a quad.
		// Retain the instance's rotation and nonuniform scale in the ray equation.
		mat3 rows = transpose(axes);
		vec2 extent = radius * vec2(length(rows[0]), length(rows[1]));
		vec3 offset = vec3(VERTEX.xy / shadow_radius * extent, 0.0);
		mat3 to_sphere = inverse(axes) / radius;
		sphere_origin = to_sphere * offset;
		sphere_ray = to_sphere * vec3(0.0, 0.0, 1.0);
		sphere_plane = (MODELVIEW_MATRIX * vec4(drift, 1.0)).xyz + offset;
		sphere_visible = 1.0;
		POSITION = PROJECTION_MATRIX * vec4(sphere_plane, 1.0);
	}
}

void fragment() {
	if (camera_layers != uint(524288) || sphere_visible < 0.5 || opacity_ratio <= 0.001 || COLOR.a <= 0.02) {
		discard;
	}
	float a = dot(sphere_ray, sphere_ray);
	float b = dot(sphere_origin, sphere_ray);
	float discriminant = b * b - a * (dot(sphere_origin, sphere_origin) - 1.0);
	if (discriminant < 0.0) {
		discard;
	}
	float front = (-b + sqrt(discriminant)) / a;
	vec4 clip = PROJECTION_MATRIX * vec4(sphere_plane + vec3(0.0, 0.0, front), 1.0);
	DEPTH = clip.z / clip.w * 0.5 + 0.5;
	vec3 encoded = fract((1.0 - DEPTH) * vec3(1.0, 255.0, 65025.0));
	encoded -= encoded.yzz * vec3(1.0 / 255.0, 1.0 / 255.0, 0.0);
	ALBEDO = encoded;
}
