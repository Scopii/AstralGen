import Globals;

[[vk::binding(0, 0)]] RWTexture2D<float4> globalImages[];
[[vk::binding(1, 0)]] StructuredBuffer<Object> globalObjectBuffers[];
[[vk::binding(1, 0)]] StructuredBuffer<CameraData> globalCameraBuffers[];
[[vk::binding(1, 0)]] RWStructuredBuffer<IndirectCommand> globalIndirectBuffers[];
[[vk::push_constant]] ConstantBuffer<PushConstants> pc;

// SHADER
[shader("compute")] 
[numthreads(1, 1, 1)]
void main(uint3 id: SV_DispatchThreadID) {

    //printf("test ID: %d\n", 1);
    uint bufIndex = pc.resources[0].index;
    RWStructuredBuffer<IndirectCommand> indirectBuffer = globalIndirectBuffers[bufIndex];

    indirectBuffer[0].groupX = 100;
    indirectBuffer[0].groupY = 100;
    indirectBuffer[0].groupZ = 100;
}