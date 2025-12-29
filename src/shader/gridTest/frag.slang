struct VertexOut {
    float4 pos : SV_Position;
    float3 color : COLOR0; // <--- Input from Mesh Shader
};

struct PushConstants {
    float4x4 viewProj;
    float4 camPosAndFov;
    float4 camDir;
    float runtime;
    uint renderImgIdx;
    uint buf1Index;
    uint buf1Count;
    uint buf2Index;
    uint buf2Count;
};

[[vk::push_constant]] ConstantBuffer<PushConstants> pc;

[shader("fragment")]
float4 main(VertexOut pin) : SV_Target {
    // ONLY if code if hit Cube.
    // background is vkCmdBeginRendering info.clearValue.
    
    // Output the color from the Mesh Shader
    return float4(pin.color, 0.5); 
}