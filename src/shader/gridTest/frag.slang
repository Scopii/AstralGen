struct VertexOut {
    float4 pos : SV_Position;
    float3 color : COLOR0; // <--- Input from Mesh Shader
};

// Push Constant
struct PushConstants {
    float4 camPosAndFov;
    float4 camDir;
    float runtime;
    uint dataCount;
    uint outputImageIndex;
    uint padding;
    float4x4 viewProj;
};

[[vk::push_constant]] ConstantBuffer<PushConstants> pc;

[shader("fragment")]
float4 main(VertexOut pin) : SV_Target {
    // We are ONLY running this code if we hit the Cube.
    // The background is already handled by vkCmdBeginRendering info.clearValue.
    
    // Output the color we calculated in the Mesh Shader
    // (This will make the cube look Red/Green/Blue interpolated)
    return float4(pin.color, 0.5); 
}