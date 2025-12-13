
struct TaskPayload {
    uint chunkID;
    float3 offset;
};
groupshared TaskPayload payload; // Data for Mesh Shader, Groupshared Memory!!

[numthreads(1, 1, 1)] // Launch 1 Thread per Task Workgroup
void main(uint3 gid: SV_GroupID) {
    bool draw = true;

    if (draw) {
        payload.chunkID = gid.x;
        payload.offset = float3(0, 0, 0);
        DispatchMesh(1, 1, 1, payload); // Spawns 1 Mesh Shader Workgroup
    } else {
        DispatchMesh(0, 0, 0, payload); // Cull => No launch
    }
}