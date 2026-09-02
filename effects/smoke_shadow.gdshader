shader_type spatial;
render_mode cull_disabled, unshaded;

uniform sampler2D albedo_texture : source_color;
uniform bool use_albedo_texture = false;
uniform bool billboard_enabled = false;
uniform float base_alpha : hint_range(0.0, 1.0) = 1.0;
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
}

void fragment() {
	if (!IN_SHADOW_PASS) {
		discard;
	}
	float particle_alpha = base_alpha * opacity_ratio * COLOR.a;
	if (use_albedo_texture) {
		particle_alpha *= texture(albedo_texture, UV).a;
	}
	ALPHA = particle_alpha;
	ALPHA_HASH_SCALE = 1.0;
}
