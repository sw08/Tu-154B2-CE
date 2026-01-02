#version 330 core

layout(location = 0) in vec2 a_pos; // screen space

uniform vec2 viewport = vec2(2048, 1504);
uniform vec4 quad_bounds = vec4(0, 0, 2048, 1504);

out vec2 v_uv; // texture coordinates for fragment shader

void main() {
    vec2 ndc = (vec2(a_pos.x, a_pos.y) / viewport) * 2.0 - 1.0;
    vec2 quad_size = quad_bounds.zw - quad_bounds.xy;
    v_uv = (a_pos - quad_bounds.xy) / quad_size;

    gl_Position = vec4(ndc, 0.0, 1.0);
}
