shader_type spatial;
render_mode cull_disabled, unshaded;

uniform bool billboard_enabled = false;
uniform float opacity_ratio : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	if (billboard_enabled) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0],
			INV_VIEW_MATRIX[1],
			INV_VIEW_MATRIX[2],
			MODEL_MATRIX[3]
		);
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
	float particle_visibility = smoothstep(0.02, 0.35, COLOR.a) * opacity_ratio;
	VERTEX *= sqrt(max(particle_visibility, 0.0));
}

void fragment() {
	if (!IN_SHADOW_PASS) {
		discard;
	}
	if (billboard_enabled && distance(UV, vec2(0.5)) > 0.5) {
		discard;
	}
	if (opacity_ratio <= 0.001 || COLOR.a <= 0.02) {
		discard;
	}
}
