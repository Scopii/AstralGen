import Globals;

[[vk::binding(0, 0)]] Texture2D<float4> heapSampledImages[];
[[vk::binding(0, 1)]] SamplerState      heapSamplers[];

[[vk::push_constant]] ConstantBuffer<CompositePushConstants> pc;

struct VertexOut {
    float4 pos : SV_Position;
    float2 uv  : TEXCOORD0;
};

[shader("fragment")]
float4 main(VertexOut pin) : SV_Target {
    Texture2D<float4> srcTex = heapSampledImages[pc.srcDesc];
    SamplerState samp = heapSamplers[pc.samplerIndex];
    bool stretch = pc.stretch != 0;

    float2 uv = pin.uv; // [0,1] from mesh shader, already covers viewport region

    if (pc.stretch == 0) {
        uint srcW, srcH;
        srcTex.GetDimensions(srcW, srcH);

        float srcAspect = float(srcW) / float(srcH);
        float dstAspect = float(pc.dstWidth) / float(pc.dstHeight);

        float2 scale = srcAspect > dstAspect
                           ? float2(dstAspect / srcAspect, 1.0)
                           : float2(1.0, srcAspect / dstAspect);

        uv = (uv - 0.5) * scale + 0.5;
        if (any(uv < 0.0) || any(uv > 1.0)) discard;
    }

    float4 color = srcTex.Sample(samp, uv);
    return float4(color.rgb, color.a * pc.opacity);
}