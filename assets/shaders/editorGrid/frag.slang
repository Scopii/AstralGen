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
    float3 rayDir = normalize(pin.worldRayTgt - rayOrigin);

    // Intersect with Floor (Y = 0 plane)
    float4 BG_COLOR = float4(0.00, 0.00, 0.1, 1.0); // dark blue-grey

    if (rayDir.y >= -0.0001) {
        FragOut o;
        o.color = BG_COLOR;
        o.depth = 1.0; // reverse-Z far plane
        return o;
    }

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
    float alpha = lineWeight * max(0.0, 1.0 - (dist / 150.0));

    // float alphaLerp = alpha; // Standard
    // float alphaLerp = lerp(0, lineWeight, alpha);
    float alphaLerp = lerp(0, alpha, 1.0 - (dist / 150.0));

    // if (alphaLerp < 0.01) discard;

    // Calculate actual depth for Z-buffer
    float4 clipPos = mul(cam.viewProj, float4(hitPos, 1.0));

    FragOut output;
    output.color = lerp(BG_COLOR, float4(color, 1.0), alphaLerp);
    output.depth = clipPos.z / clipPos.w;
    return output;
}