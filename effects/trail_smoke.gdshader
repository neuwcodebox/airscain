shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

#include "res://effects/trail_motion.gdshaderinc"
uniform sampler2D puff_texture : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform float opacity_ratio = 1.0;
varying float puff_alpha;

void vertex() {
	vec4 motion = trail_motion(INSTANCE_CUSTOM, COLOR.rgb);
	puff_alpha = trail_alpha(INSTANCE_CUSTOM) * COLOR.a;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(MODEL_MATRIX[3].xyz + motion.xyz, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	// Zero-alpha cards must not keep rasterizing a full billboard until cleanup.
	VERTEX *= puff_alpha * opacity_ratio > 0.0 ? motion.w : 0.0;
}

void fragment() {
	vec4 puff = texture(puff_texture, UV);
	ALBEDO = tint.rgb * puff.rgb;
	ALPHA = tint.a * puff.a * puff_alpha * opacity_ratio;
}
