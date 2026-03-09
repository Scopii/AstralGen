import Globals;

struct VertexOut {
    float4 pos : SV_Position;
    float3 worldRayTgt : TEXCOORD0; // The target point on the far plane
};

[[vk::binding(0, 0)]] ConstantBuffer<CameraData> heapCameraBuffers[];
[[vk::push_constant]] ConstantBuffer<PushConstants> pc;[shader("mesh")]
[outputtopology("triangle")]
[numthreads(1, 1, 1)]
void main(out vertices VertexOut verts[4], out indices uint3 tris[2]) {
    ConstantBuffer<CameraData> cam = heapCameraBuffers[pc.resources[0]];
    SetMeshOutputCounts(4, 2);

    // Fullscreen Quad (NDC)
    float2 ndc[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };

    // (-1, -1) is Top-Left in Vulkan -> Zig Index 6
    // ( 1, -1) is Top-Right in Vulkan -> Zig Index 7
    // (-1,  1) is Bottom-Left in Vulkan -> Zig Index 4
    // ( 1,  1) is Bottom-Right in Vulkan -> Zig Index 5
    uint farIdx[4] = { 6, 7, 4, 5 };

    for (int i = 0; i < 4; i++) {
        verts[i].pos = float4(ndc[i], 1.0, 1.0); // Z=1 ensures it draws behind everything
        verts[i].worldRayTgt = cam.frustumCorners[farIdx[i]].xyz;
    }

    tris[0] = uint3(0, 1, 2);
    tris[1] = uint3(2, 1, 3);
}