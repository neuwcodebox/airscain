shader_type canvas_item;

void fragment() {
	float left = 1.0 - smoothstep(0.22, 0.78, UV.x);
	float edge = smoothstep(0.25, 0.8, abs(UV.y - 0.5));
	COLOR = vec4(0.018, 0.038, 0.048, clamp(left * 0.94 + edge * 0.3, 0.10, 0.97));
}
