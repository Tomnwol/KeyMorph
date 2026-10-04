shader_type canvas_item;
// UV mode: Bounding Box
// UV.x / UV.y = normalized position inside the shape's axis-aligned bounds.

uniform vec4 tint : source_color = vec4(1.0, 0.55, 0.2, 0.9);
uniform float speed : hint_range(0.0, 8.0, 0.1) = 1.5;
uniform float bands : hint_range(1.0, 12.0, 0.1) = 3.0;

void fragment() {
	float band = fract(UV.y * bands - TIME * speed);
	float glow = smoothstep(0.0, 0.12, band) * smoothstep(0.45, 0.12, band);
	float alpha = (0.2 + glow * 0.8) * tint.a * COLOR.a;
	COLOR = vec4(tint.rgb * (0.55 + glow * 0.45), alpha);
}
