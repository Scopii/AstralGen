struct VSOutput {
    float4 pos : SV_Position;
};

// (CCW winding: Bottom-Left, Bottom-Right, Top-Left)
static const float2 positions[3] = {
    float2(-1, -1), 
    float2(3, -1), 
    float2(-1, 3)
};

VSOutput main(uint vID : SV_VertexID) {
    VSOutput output;
    // Map to Vulkan Clip Space (0,0 to 1,1 is standard, but full screen is -1 to 1)
    output.pos = float4(positions[vID], 0.0, 1.0);
    return output;
}
