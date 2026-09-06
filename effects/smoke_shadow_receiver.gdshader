shader_type spatial;
render_mode diffuse_burley;
#include "res://effects/smoke_shadow_sampling.gdshaderinc"
uniform vec4 base_color : source_color = vec4(1.0);
uniform float surface_roughness = 0.9;
varying vec3 receiver_position;
void vertex() { receiver_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	ALBEDO = base_color.rgb * (1.0 - projected_smoke_shadow(receiver_position));
	ROUGHNESS = surface_roughness;
}
