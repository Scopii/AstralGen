
struct VertexOut {
    float4 pos : SV_Position;
    float3 color : COLOR0;
};

struct TaskPayload {
    uint chunkId;
};

// Simple Triangle
static const float3 positions[3] = {
    float3(-0.5, 0.5, 0.0),
    float3(0.5, 0.5, 0.0),
    float3(0.0, -0.5, 0.0)
};

struct CameraData {
    float4x4 viewProj;
    float4 camPosAndFov;
    float4 camDir;
};

struct Resource {
    uint index;
    uint count;
};

struct PushConstants {
    float runtime;
    float deltaTime;
    uint width;
    uint height;
    Resource resources[14];
};

[[vk::binding(0, 0)]] RWTexture2D<float4> globalImages[];
[[vk::binding(1, 0)]] StructuredBuffer<CameraData> globalCameraBuffers[];
[[vk::push_constant]] ConstantBuffer<PushConstants> pc;

[shader("mesh")]
[outputtopology("triangle")]
[numthreads(1, 1, 1)]
void main(
    in payload TaskPayload payload,
    out vertices VertexOut verts[3],
    out indices uint3 tris[1]
) {
    SetMeshOutputCounts(3, 1);

    // Offset position based on ID from Dispatch
    float xOffset = (float(payload.chunkId) - 1.0) * 0.6;

    for (uint i = 0; i < 3; i++) {
        verts[i].pos = float4(positions[i] + float3(xOffset, 0, 0), 1.0);

        // Different color per chunk
        if (payload.chunkId == 0) verts[i].color = float3(1, 0, 0);
        else if (payload.chunkId == 1) verts[i].color = float3(0, 1, 0);
        else verts[i].color = float3(0, 0, 1);
    }

    tris[0] = uint3(0, 1, 2);
}