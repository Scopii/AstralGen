
struct TaskPayload {
    uint chunkID;
    float3 offset;
};

struct VertexOut {
    float4 pos : SV_Position;
    float3 color : COLOR0;
};

[outputtopology("triangle")]
[numthreads(1, 1, 1)] // workgroup
void main(
    in payload TaskPayload payload, // Read only Task Shader Input
    out vertices VertexOut verts[3],
    out indices uint3 tris[1]
) {
    SetMeshOutputCounts(3, 1); // Output for this Workgroup: 3 vertices, 1 triangle
    //float3 posOffset = payload.offset; // Payload Example

    verts[0].pos = float4(float3(-1, -1, 0), 1.0);
    verts[0].color = float3(1, 0, 0);

    verts[1].pos = float4(float3(3, -1, 0), 1.0);
    verts[1].color = float3(0, 1, 0);

    verts[2].pos = float4(float3(-1, 3, 0), 1.0);
    verts[2].color = float3(0, 0, 1);

    tris[0] = uint3(0, 1, 2);
}