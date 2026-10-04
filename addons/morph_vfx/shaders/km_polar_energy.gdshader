shader_type canvas_item;
// UV mode: Polar
// UV.x = angle 0..1 around centroid, UV.y = radius 0 (center) .. 1 (rim).

uniform vec4 tint : source_color = vec4(0.25, 0.85, 1.0, 0.95);
uniform float time_scale : hint_range(0.0, 8.0, 0.1) = 2.0;
uniform float rings : hint_range(1.0, 16.0, 0.1) = 5.0;
uniform float core : hint_range(0.0, 1.0, 0.01) = 0.15;

void fragment() {
	float angle = UV.x;
	float radius = UV.y;
	float wave = sin((radius * rings - TIME * time_scale + angle) * TAU) * 0.5 + 0.5;
	float rim = smoothstep(1.0, 0.65, radius);
	float hole = smoothstep(core, core + 0.12, radius);
	float alpha = rim * hole * (0.3 + 0.7 * wave) * tint.a * COLOR.a;
	vec3 rgb = tint.rgb * (0.5 + 0.5 * wave);
	COLOR = vec4(rgb, alpha);
}
