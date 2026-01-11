
struct VertexOut {
    float4 pos : SV_Position;
    float3 color : COLOR0;
};

struct TaskPayload {
    float3 baseOffset;
};

static const float3 cubeVerts[8] = {
    float3(-1, -1, -1), 
    float3( 1, -1, -1), 
    float3(-1,  1, -1), 
    float3( 1,  1, -1), 
    float3(-1, -1,  1), 
    float3( 1, -1,  1), 
    float3(-1,  1,  1), 
    float3( 1,  1,  1)  
};

static const uint3 cubeIndices[12] = {
    uint3(2, 1, 0), uint3(1, 2, 3),
    uint3(4, 5, 6), uint3(5, 7, 6),
    uint3(0, 4, 6), uint3(6, 2, 0),
    uint3(1, 3, 7), uint3(7, 5, 1),
    uint3(0, 1, 5), uint3(5, 4, 0),
    uint3(2, 6, 7), uint3(7, 3, 2)
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
    in payload TaskPayload p,
    uint3 gid: SV_GroupID, // cube ID
    out vertices VertexOut verts[8],
    out indices uint3 tris[12]
) {
    SetMeshOutputCounts(8, 12);
    StructuredBuffer<CameraData> camData = globalCameraBuffers[pc.resources[0].index];
    CameraData cam = camData[0];

    // Position based on the Group ID + Payload Base
    float3 myGridPos = float3(gid.x, gid.y, gid.z);
    float3 worldPosOffset = p.baseOffset + (myGridPos * 2.5); // Space in between

    for (uint i = 0; i < 8; ++i) {
        float3 localPos = cubeVerts[i];
        float4 worldPos = float4(localPos + worldPosOffset, 1.0);

        verts[i].pos = mul(cam.viewProj, worldPos);

        verts[i].color = myGridPos / 10.0;
    }

    for (uint i = 0; i < 12; ++i) {
        tris[i] = cubeIndices[i];
    }
}