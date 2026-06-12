import Globals;

struct ImGuiPushConstants {
    float2 scale;
    float2 translate;
    uint texDesc;
};

[[vk::push_constant]] ConstantBuffer<ImGuiPushConstants> pc;

struct VSInput {
    [[vk::location(0)]] float2 pos : POSITION;
    [[vk::location(1)]] float2 uv : TEXCOORD0;
    [[vk::location(2)]] float4 color : COLOR0;
};

struct VSOutput {
    float4 pos : SV_Position;
    float2 uv : TEXCOORD0;
    float4 color : COLOR0;
};

[shader("vertex")]
VSOutput main(VSInput input) {
    VSOutput output;
    output.pos = float4(input.pos * pc.scale + pc.translate, 0.0, 1.0);
    output.uv = input.uv;
    output.color = input.color;
    return output;
}