import Globals;

[[vk::constant_id(0)]] const uint THREAD_X = 8;
[[vk::constant_id(1)]] const uint THREAD_Y = 8;
[[vk::constant_id(2)]] const uint THREAD_Z = 1;

[[vk::binding(0, 0)]] RWTexture2D<float4>        heapRWImages[];
[[vk::binding(0, 0)]] Texture2D<float4> heapSampledImages[]; 
[[vk::binding(0, 0)]] ConstantBuffer<CameraData> heapCameraBuffers[];
[[vk::binding(0, 1)]] SamplerState heapSamplers[];

[[vk::push_constant]] ConstantBuffer<PushConstants> pc;

[shader("compute")]
[numthreads(THREAD_X, THREAD_Y, THREAD_Z)]
void main(uint3 id: SV_DispatchThreadID) {
    if (id.x >= pc.width || id.y >= pc.height) return;

    RWTexture2D<float4>        outImg   = heapRWImages[pc.resources[0]];
    Texture2D<float4>          depthTex = heapSampledImages[pc.resources[1]];
    SamplerState               samp     = heapSamplers[1]; // 1 is nearest sampler
    ConstantBuffer<CameraData> cam      = heapCameraBuffers[pc.resources[3]];

    float2 uv = (float2(id.xy) + 0.5) / float2(pc.width, pc.height);

    float rawDepth = depthTex.SampleLevel(samp, uv, 0.0).r;
    // float rawDepth = depthTex.Load(int3(id.xy, 0)).r; Optional Load

    float near = cam.nearAndFar.x;
    float far = cam.nearAndFar.y;
    float linearDepth = (near * far) / (far - rawDepth * (far - near));

    // float t = saturate(linearDepth / far);
    float t = saturate((linearDepth - near) / (far - near));

    float3 color;
    if (rawDepth >= 1.0) {
        color = float3(0, 0, 0);
    } else color = lerp(float3(0.0, 0.2, 1.0), float3(1.0, 0.1, 0.0), t); 

    outImg[id.xy] = float4(color, 1.0);
}