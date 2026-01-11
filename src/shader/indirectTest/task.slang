
struct TaskPayload {
    uint chunkId;
};


[shader("amplification")]
[numthreads(1, 1, 1)]
void main(uint3 gid: SV_GroupID) {
    TaskPayload payload;
    payload.chunkId = gid.x;

    DispatchMesh(1, 1, 1, payload); // 1 Mesh Workgroup per Task Workgroup
}