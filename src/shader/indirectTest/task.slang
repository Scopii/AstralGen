struct TaskPayload {
    uint chunkId;
};

// groupshared TaskPayload payload; 

[shader("amplification")]
[numthreads(1, 1, 1)]
void main(uint3 gid: SV_GroupID) {
    TaskPayload payload;
    payload.chunkId = gid.x;

    // 1 Mesh Workgroup per Task Workgroup
    DispatchMesh(1, 1, 1, payload);
}