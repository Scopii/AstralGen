import Globals;

struct VertexOut {
    float4 pos : SV_Position;
    float3 color : COLOR0;
};

// Cube Vertices (Size 2.0)
static const float3 cubeVerts[8] = {
    float3(-1, -1, -1), float3( 1, -1, -1), 
    float3(-1,  1, -1), float3( 1,  1, -1), 
    float3(-1, -1,  1), float3( 1, -1,  1), 
    float3(-1,  1,  1), float3( 1,  1,  1)  
};

// Cube (Clockwise)
static const uint3 cubeIndices[12] = {
    uint3(0, 1, 2), uint3(2, 1, 3), // Front
    uint3(4, 6, 5), uint3(6, 7, 5), // Back
    uint3(0, 2, 4), uint3(4, 2, 6), // Left
    uint3(1, 5, 3), uint3(5, 7, 3), // Right
    uint3(0, 4, 1), uint3(4, 5, 1), // Bottom
    uint3(2, 3, 6), uint3(6, 3, 7)  // Top
};

// Alternative Line Indices
static const uint2 lineIndices[12] = {
    uint2(0, 1), uint2(1, 3), uint2(3, 2), uint2(2, 0), // Bottom Face
    uint2(4, 5), uint2(5, 7), uint2(7, 6), uint2(6, 4), // Top Face
    uint2(0, 4), uint2(1, 5), uint2(3, 7), uint2(2, 6)  // Connecting Pillars
};

// Images
[[vk::binding(0, 0)]] RWTexture2D<float4> heapRWImages[];
[[vk::binding(0, 0)]] Texture2D<float4> heapSampledImages[];
// Buffers
[[vk::binding(0, 0)]] StructuredBuffer<Object> heapObjectBuffers[];
[[vk::binding(0, 0)]] ConstantBuffer<CameraData> heapCameraBuffers[];
[[vk::binding(0, 0)]] RWStructuredBuffer<IndirectCommand> heapIndirectBuffers[];

[[vk::push_constant]] ConstantBuffer<PushConstants> pc;

[shader("mesh")]
[outputtopology("Triangle")]
[numthreads(1, 1, 1)]
void main(
    uint3 groupId: SV_GroupID, // From Indirect Buffer
    out vertices VertexOut verts[8],
    out indices uint3 tris[12]
    // out indices uint2 outLines[12]
) {
    SetMeshOutputCounts(8, 12);

    ConstantBuffer<CameraData> cam = heapCameraBuffers[pc.resources[1]];

    float3 gridPos = float3(groupId.x, groupId.y, groupId.z) * 4.00; // World Pos of Cube

    float3 worldOrigin = gridPos - float3(15.0, 15.0, 15.0); // Offset grid

    for (uint i = 0; i < 8; ++i) {
        float3 worldPos = cubeVerts[i] + worldOrigin; // Local Cube Pos + Grid Offset

        verts[i].pos = mul(cam.viewProj, float4(worldPos, 1.0)); // Project to Screen

        // Color
        // verts[i].color = float3(groupId.x, groupId.y, groupId.z) / 10.0;
        verts[i].color = hashColor(groupId);
        // verts[i].color = float3(0.0, 0.0, 1);
    }

    for (uint i = 0; i < 12; ++i) {
        tris[i] = cubeIndices[i];
        // outLines[i] = lineIndices[i];
    }
}