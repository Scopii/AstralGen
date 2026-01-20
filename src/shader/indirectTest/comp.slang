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

    globalIndirectBuffers[bufIndex][0].groupX = 3;
    globalIndirectBuffers[bufIndex][0].groupY = 1;
    globalIndirectBuffers[bufIndex][0].groupZ = 1;

    globalIndirectBuffers[bufIndex][0].count = 3; // debug count
}