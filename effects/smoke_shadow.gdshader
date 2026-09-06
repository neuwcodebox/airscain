shader_type spatial;
render_mode cull_disabled, unshaded, fog_disabled;
varying flat uint camera_layers;

#include "res://effects/trail_motion.gdshaderinc"
uniform bool trail_enabled = false;

uniform bool billboard_enabled = false;
uniform float opacity_ratio : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	camera_layers = CAMERA_VISIBLE_LAYERS;
	if (billboard_enabled) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0],
			INV_VIEW_MATRIX[1],
			INV_VIEW_MATRIX[2],
			MODEL_MATRIX[3]
		);
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
	float alpha = trail_enabled ? trail_alpha(INSTANCE_CUSTOM) : COLOR.a;
	float particle_visibility = smoothstep(0.02, 0.35, alpha) * opacity_ratio;
	VERTEX *= sqrt(max(particle_visibility, 0.0));
	if (trail_enabled) {
		vec4 motion = trail_motion(INSTANCE_CUSTOM, COLOR.rgb);
		VERTEX = VERTEX * motion.w + motion.xyz;
	}
}

void fragment() {
	if (!IN_SHADOW_PASS && camera_layers != uint(524288)) {
		discard;
	}
	if (billboard_enabled && distance(UV, vec2(0.5)) > 0.5) {
		discard;
	}
	if (opacity_ratio <= 0.001 || COLOR.a <= 0.02) {
		discard;
	}
	vec3 encoded = fract((1.0 - FRAGCOORD.z) * vec3(1.0, 255.0, 65025.0));
	encoded -= encoded.yzz * vec3(1.0 / 255.0, 1.0 / 255.0, 0.0);
	ALBEDO = encoded;
}
