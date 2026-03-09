import Globals;

[[vk::binding(0, 0)]] ConstantBuffer<CameraData> heapCameraBuffers[];
[[vk::push_constant]] ConstantBuffer<PushConstants> pc;

struct VertexOut {
    float4 pos : SV_Position;
    float3 worldRayTgt : TEXCOORD0;
};

struct FragOut {
    float4 color : SV_Target;
    float depth  : SV_Depth; 
};

[shader("fragment")]
FragOut main(VertexOut pin) {
    ConstantBuffer<CameraData> cam = heapCameraBuffers[pc.resources[0]];

    float3 rayOrigin = cam.camPosAndFov.xyz;
    // The hardware interpolates worldRayTgt perfectly for every pixel!
    float3 rayDir = normalize(pin.worldRayTgt - rayOrigin);

    // Intersect with Floor (Y = 0 plane)
    if (rayDir.y >= -0.0001) discard; // Looking up at the sky

    float t = -rayOrigin.y / rayDir.y;
    float3 hitPos = rayOrigin + rayDir * t;

    // Grid Math
    float gridSize = 1.0; 
    float2 gridUV = hitPos.xz / gridSize;

    // Anti-aliased lines
    float2 gridDeriv = fwidth(gridUV);
    float2 gridLine = abs(fract(gridUV - 0.5) - 0.5) / gridDeriv;
    float lineVal = min(gridLine.x, gridLine.y);
    float lineWeight = 1.0 - min(lineVal, 1.0);

    // Axis Colors (Red = X, Blue = Z)
    float3 color = float3(0.3, 0.3, 0.3); 
    if (abs(hitPos.z) < 0.05) color = float3(1.0, 0.2, 0.2); 
    if (abs(hitPos.x) < 0.05) color = float3(0.2, 0.5, 1.0); 

    // Distance Fade
    float dist = length(hitPos - rayOrigin);
    float alpha = lineWeight * max(0.0, 1.0 - (dist / 100.0));
    if (alpha < 0.01) discard;

    // Calculate actual depth for the Z-buffer
    float4 clipPos = mul(cam.viewProj, float4(hitPos, 1.0));
    
    FragOut out;
    out.color = float4(color, alpha);
    out.depth = clipPos.z / clipPos.w;
    return out;
}