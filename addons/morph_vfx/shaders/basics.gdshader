shader_type canvas_item;

float distance_to_center(vec2 uv) {
    return distance(uv, vec2(0.5));
}

void fragment() {
    float dist = distance_to_center(UV);

    COLOR = vec4(vec3(dist), 1.0);
}
