
struct VSOutput {
    float4 pos : SV_Position;
};

// (CCW Bottom-Left, Bottom-Right, Top-Left)
static const float2 positions[3] = {
    float2(-1, -1),
    float2(-1, 3),
    float2(3, -1)
};

[shader("vertex")]
VSOutput main(uint vID : SV_VertexID) {
    VSOutput output;
    output.pos = float4(positions[vID], 0.0, 1.0);
    return output;
}