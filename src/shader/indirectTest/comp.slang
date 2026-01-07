
struct Object {
    float posX; float posY; float posZ; float size;     
    float colorR; float colorG; float colorB; uint sdfId; 
    uint4 _padding; 
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

struct IndirectCommand {
    uint groupX;
    uint groupY;
    uint groupZ;
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
[[vk::binding(1, 0)]] StructuredBuffer<Object> globalObjectBuffers[];
[[vk::binding(1, 0)]] StructuredBuffer<CameraData> globalCameraBuffers[];
[[vk::binding(1, 0)]] RWStructuredBuffer<IndirectCommand> globalIndirectBuffers[];
[[vk::push_constant]] ConstantBuffer<PushConstants> pc;

// SHADER
[shader("compute")] 
[numthreads(1, 1, 1)]
void main(uint3 id: SV_DispatchThreadID) {
    uint bufIndex = pc.resources[0].index;

    globalIndirectBuffers[bufIndex][0].groupX = 3;
    globalIndirectBuffers[bufIndex][0].groupY = 1;
    globalIndirectBuffers[bufIndex][0].groupZ = 1;

    // Optional: Write debug count
    globalIndirectBuffers[bufIndex][0].count = 3;
}