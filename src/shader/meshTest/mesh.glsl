#version 450
#extension GL_EXT_mesh_shader : require

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in; // workgroup
layout(max_vertices = 3, max_primitives = 1) out;
layout(triangles) out; // primitive type

// Data passed to fragment shader
layout(location = 0) out PerVertex {
    vec3 color;
} outVertices[];

void main() {
    SetMeshOutputsEXT(3, 1); // Output for this Workgroup: 3 vertices, 1 triangle

    // Vertex 1
    gl_MeshVerticesEXT[0].gl_Position = vec4(-1, -1, 0.0, 1.0);
    outVertices[0].color = vec3(1.0, 0.0, 0.0); // Red
    // Vertex 3
    gl_MeshVerticesEXT[1].gl_Position = vec4(3, -1, 0.0, 1.0);
    outVertices[1].color = vec3(0.0, 1.0, 0.0); // Green
    // Vertex 3
    gl_MeshVerticesEXT[2].gl_Position = vec4(-1, 3, 0.0, 1.0);
    outVertices[2].color = vec3(0.0, 0.0, 1.0); // Blue
    
    gl_PrimitiveTriangleIndicesEXT[0] = uvec3(0, 1, 2);
}