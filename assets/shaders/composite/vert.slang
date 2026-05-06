import Globals;

struct VertexOut {
    float4 pos : SV_Position;
    float2 uv  : TEXCOORD0;
};

[shader("vertex")]
VertexOut main(uint vertId: SV_VertexID) {
    VertexOut output;
    output.uv  = float2((vertId << 1) & 2, vertId & 2);
    output.pos = float4(output.uv * 2.0 - 1.0, 0.0, 1.0);
    return output;
}