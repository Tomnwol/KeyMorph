shader_type canvas_item;
// Rocks (Voronoi cells) + animated lava in the cracks. Uses Bounding Box UV.

uniform vec4 rock_dark : source_color = vec4(0.18, 0.16, 0.15, 1.0);
uniform vec4 rock_light : source_color = vec4(0.42, 0.38, 0.34, 1.0);
uniform vec4 lava_cool : source_color = vec4(0.55, 0.08, 0.02, 1.0);
uniform vec4 lava_hot : source_color = vec4(1.0, 0.72, 0.15, 1.0);
uniform float scale : hint_range(2.0, 24.0, 0.1) = 7.0;
uniform float crack_width : hint_range(0.01, 0.25, 0.001) = 0.07;
uniform float lava_speed : hint_range(0.0, 6.0, 0.1) = 1.4;
uniform float glow : hint_range(0.0, 3.0, 0.05) = 1.35;


vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}


// Returns: x = dist to nearest cell edge, y = cell id hash
vec2 voronoi_edge(vec2 uv) {
	vec2 g = floor(uv);
	vec2 f = fract(uv);
	float min_d1 = 8.0;
	float min_d2 = 8.0;
	vec2 closest_id = vec2(0.0);

	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 cell = vec2(float(i), float(j));
			vec2 offset = hash2(g + cell);
			vec2 r = cell + offset - f;
			float d = length(r);
			if (d < min_d1) {
				min_d2 = min_d1;
				min_d1 = d;
				closest_id = g + cell;
			} else if (d < min_d2) {
				min_d2 = d;
			}
		}
	}
	float edge = min_d2 - min_d1;
	float id = hash2(closest_id).x;
	return vec2(edge, id);
}


float rock_noise(vec2 uv) {
	vec2 i = floor(uv);
	vec2 f = fract(uv);
	float a = hash2(i).x;
	float b = hash2(i + vec2(1.0, 0.0)).x;
	float c = hash2(i + vec2(0.0, 1.0)).x;
	float d = hash2(i + vec2(1.0, 1.0)).x;
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}


void fragment() {
	vec2 uv = UV * scale;
	vec2 v = voronoi_edge(uv);
	float edge = v.x;
	float cell = v.y;

	// Soft lava mask in the cracks between cells.
	float crack = 1.0 - smoothstep(0.0, crack_width, edge);
	crack = pow(crack, 1.35);

	// Animated lava.
	float flow = rock_noise(UV * 10.0 + vec2(TIME * lava_speed * 0.35, TIME * lava_speed * -0.2));
	float pulse = 0.55 + 0.45 * sin(TIME * lava_speed * 2.2 + cell * 6.2831 + flow * 4.0);
	vec3 lava = mix(lava_cool.rgb, lava_hot.rgb, pulse * flow);
	lava *= 1.0 + glow * crack * pulse;

	// Rocky surface shading per cell.
	float grain = rock_noise(UV * 28.0 + cell * 12.0);
	float shade = 0.75 + 0.25 * cell + 0.15 * (grain - 0.5);
	vec3 rock = mix(rock_dark.rgb, rock_light.rgb, shade);
	// Slight bevel near cracks.
	rock *= 0.85 + 0.15 * smoothstep(0.0, crack_width * 2.5, edge);

	vec3 rgb = mix(rock, lava, crack);
	float alpha = COLOR.a;
	COLOR = vec4(rgb, alpha);
}
