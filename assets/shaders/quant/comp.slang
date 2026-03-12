import Globals;

[[vk::binding(0, 0)]] RWTexture2D<float4> heapRWImages[];
[[vk::binding(0, 0)]] Texture2D<float4> heapSampledImages[];
[[vk::binding(0, 0)]] StructuredBuffer<Object> heapObjectBuffers[];
[[vk::binding(0, 0)]] ConstantBuffer<CameraData> heapCameraBuffers[];
[[vk::binding(0, 0)]] RWStructuredBuffer<IndirectCommand> heapIndirectBuffers[];

[[vk::push_constant]] ConstantBuffer<PushConstants> pc;

// 0 = Full Frustum, 1 = Z split, 2 = ZX split, 3 = ZXY split
static const uint SUBDIVISION_LEVEL = 10; 

[shader("compute")] 
[numthreads(1, 1, 1)]
void main(uint3 id: SV_DispatchThreadID) {
    RWStructuredBuffer<IndirectCommand> indirectBuffer = heapIndirectBuffers[pc.resources[0]];

    // The number of cells is exactly 2^Level
    uint cellCount = 1u << SUBDIVISION_LEVEL;

    // We dispatch 1 Mesh Workgroup per Cell
    indirectBuffer[0].groupX = cellCount;
    indirectBuffer[0].groupY = 1;
    indirectBuffer[0].groupZ = 1;
}