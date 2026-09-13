shader_type canvas_item;

uniform vec4 damage_color : source_color = vec4(0.86, 0.035, 0.015, 0.72);
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float edge_width_pixels : hint_range(1.0, 240.0) = 110.0;

void fragment() {
	vec2 edge_pixels = min(UV, vec2(1.0) - UV) / SCREEN_PIXEL_SIZE;
	float nearest_edge = min(edge_pixels.x, edge_pixels.y);
	float edge_alpha = 1.0 - smoothstep(0.0, edge_width_pixels, nearest_edge);
	edge_alpha *= edge_alpha;
	COLOR = vec4(damage_color.rgb, damage_color.a * strength * edge_alpha);
}
