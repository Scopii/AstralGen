import Globals;

// Images
[[vk::binding(0, 0)]] RWTexture2D<float4> heapRWImages[];
[[vk::binding(0, 0)]] Texture2D<float4> heapSampledImages[];
// Buffers
[[vk::binding(0, 0)]] StructuredBuffer<Object> heapObjectBuffers[];
[[vk::binding(0, 0)]] ConstantBuffer<CameraData> heapCameraBuffers[];
[[vk::binding(0, 0)]] RWStructuredBuffer<IndirectCommand> heapIndirectBuffers[];

[[vk::push_constant]] ConstantBuffer<PushConstants> pc;

// SHADER
[shader("compute")] 
[numthreads(1, 1, 1)]
void main(uint3 id: SV_DispatchThreadID) {

    //printf("test ID: %d\n", 1);
    RWStructuredBuffer<IndirectCommand> indirectBuffer = heapIndirectBuffers[pc.resources[0]];
    StructuredBuffer<Object> objectBuffer = heapObjectBuffers[pc.resources[1]];

    indirectBuffer[0].groupX = objectBuffer.getCount();
    indirectBuffer[0].groupY = 100;
    indirectBuffer[0].groupZ = 100;
}