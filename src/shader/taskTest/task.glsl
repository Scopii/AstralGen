#version 460
#extension GL_EXT_mesh_shader : require

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in; // Launch 1 Thread per Task Workgroup

struct TaskPayload {
    uint chunkID;
    vec3 offset; 
};
taskPayloadSharedEXT TaskPayload payload; // Data for Mesh Shader, Groupshared Memory!!

void main() {
    bool draw = true; 

    if (draw) {
        payload.chunkID = gl_WorkGroupID.x; 
        payload.offset = vec3(0.0, 0.0, 0.0);
        EmitMeshTasksEXT(1, 1, 1); // Spawns 1 Mesh Shader Workgroup
    } else {
        EmitMeshTasksEXT(0, 0, 0); // Cull => No launch
    }
}