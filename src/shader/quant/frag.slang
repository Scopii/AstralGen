
struct VertexOut {
    float4 pos : SV_Position;
    float3 color : COLOR0; // Mesh Shader Input
};

[shader("fragment")]
float4 main(VertexOut pin) : SV_Target {
    // ONLY if cube is hit.
    return float4(pin.color, 1); 
}