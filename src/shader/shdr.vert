#version 450

vec2 positions[3] = vec2[](
    vec2(-1.0, -3.0),// Top Left
    vec2(3.0, 1.0),  // Bottom Right
    vec2(-1.0, 1.0)  // Bottom Left
);

void main() {
    gl_Position = vec4(positions[gl_VertexIndex], 0.0, 1.0);
}