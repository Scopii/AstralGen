import Globals;

struct ImGuiPushConstants {
    float2 scale;
    float2 translate;
    uint texDesc;
};

[[vk::push_constant]] ConstantBuffer<ImGuiPushConstants> pc;
[[vk::binding(0, 0)]] Texture2D<float4> heapSampledImages[];

struct VSOutput {
    float4 pos : SV_Position;
    float2 uv : TEXCOORD0;
    float4 color : COLOR0;
};

[shader("fragment")]
float4 main(VSOutput pin) : SV_Target {
    Texture2D<float4> tex = heapSampledImages[pc.texDesc];

    uint width, height;
    tex.GetDimensions(width, height);

    // Exact 1:1 pixel mapping
    uint2 texCoord = clamp(uint2(pin.uv * float2(width, height)), uint2(0, 0), uint2(width - 1, height - 1));
    return pin.color * tex.Load(int3(texCoord, 0));
}