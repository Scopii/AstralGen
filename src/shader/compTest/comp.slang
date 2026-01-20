import Globals;

[[vk::binding(0, 0)]] RWTexture2D<float4> globalImages[];
[[vk::binding(1, 0)]] StructuredBuffer<Object> globalObjectBuffers[];
[[vk::binding(1, 0)]] RWStructuredBuffer<ReadbackData> globalReadbacks[];
[[vk::binding(1, 0)]] StructuredBuffer<CameraData> globalCameraBuffers[];
[[vk::push_constant]] ConstantBuffer<PushConstants> pc;

// Marching Constants
static const int MAX_STEPS = 512;
static const float MIN_DIST = 0.001;
static const float MAX_DIST = 200.0;
// Other Constants
static const float EPSILON = 0.001;

MapResult map(float3 pos, StructuredBuffer<Object> objectBuffer) {
    float closestDist = MAX_DIST;
    int closestIndex = -1;

    uint objectCount = pc.resources[0].count;

    for (uint i = 0; i < objectCount; i++) {
        Object obj = objectBuffer[i];
        float3 objPos = float3(obj.posX, obj.posY, obj.posZ);

        float dist = MAX_DIST;
        if (obj.sdfId == 0) dist = sdSphere(pos - objPos, obj.size);
        else if (obj.sdfId == 1) dist = sdBox(pos - objPos, float3(obj.size));
        else dist = sdTorus(pos - objPos, float2(obj.size));

        if (dist < closestDist) {
            closestDist = dist;
            closestIndex = i;
        }
    }

    MapResult res;
    res.dist = closestDist;
    res.index = closestIndex;
    return res;
}

// Normal Functions
float3 getNormal(float3 pos, StructuredBuffer<Object> objectBuffer) {
    return normalize(float3(
        map(pos + float3(EPSILON, 0, 0), objectBuffer).dist - map(pos - float3(EPSILON, 0, 0), objectBuffer).dist,
        map(pos + float3(0, EPSILON, 0), objectBuffer).dist - map(pos - float3(0, EPSILON, 0), objectBuffer).dist,
        map(pos + float3(0, 0, EPSILON), objectBuffer).dist - map(pos - float3(0, 0, EPSILON), objectBuffer).dist
    ));
}

// SHADER
[shader("compute")] 
[numthreads(8, 8, 1)]
void main(uint3 id: SV_DispatchThreadID) {
    RWStructuredBuffer<ReadbackData> readback = globalReadbacks[pc.resources[3].index];
    readback[0].runtime = pc.runtime;
    readback[0].deltaTime = pc.deltaTime;
    readback[0].width = pc.width;
    readback[0].height = pc.height;

    RWTexture2D<float4> renderImg = globalImages[pc.resources[2].index];
    StructuredBuffer<Object> objectBuffer = globalObjectBuffers[pc.resources[0].index];
    StructuredBuffer<CameraData> camData = globalCameraBuffers[pc.resources[1].index];
    CameraData cam = camData[0];

    // Bounds check (because group size is 8x8)
    uint renderWidth = pc.width;
    uint renderHeight = pc.height;
    if (id.x >= renderWidth || id.y >= renderHeight) return;

    float2 uv = (float2(id.xy) / float2(renderWidth, renderHeight)) * 2.0 - 1.0;

    float3 camForward = normalize(cam.camDir.xyz);
    float3 camRight = normalize(cross(camForward, float3(0, 1, 0)));
    float3 camUp = normalize(cross(camRight, camForward));

    float focalLength = 1.0 / tan(radians(cam.camPosAndFov.w * 0.5));
    float aspectRatio = float(renderWidth) / float(renderHeight);
    float3 rayDirection = normalize(uv.x * camRight * aspectRatio - uv.y * camUp + focalLength * camForward);
    
    // Raymarching
    float march = 0.0;
    bool hit = false;
    float3 pos = float3(0,0,0);
    int hitIndex = -1;
    
    // Slang loop attribute
    [loop]
    for (int step = 0; step < MAX_STEPS; step++) {
        pos = cam.camPosAndFov.xyz + rayDirection * march;
        MapResult result = map(pos, objectBuffer);

        if (result.dist < MIN_DIST) {
            hit = true;
            hitIndex = result.index; // Safe capture
            break;
        }
        march += result.dist;
        if(march > MAX_DIST) break;
    }
    
    // Output
    if (hit && hitIndex != -1) {
        float3 normal = getNormal(pos, objectBuffer);
        float3 lightDir = normalize(float3(1.0, 1.0, -1.0));
        float lighting = max(dot(normal, lightDir), 0.1);

        Object hitObj = objectBuffer[hitIndex];
        float3 surfaceColor = float3(hitObj.colorR, hitObj.colorG, hitObj.colorB);
        
        float4 finalColor = lerp(float4(surfaceColor * lighting, 1.0), float4(0.0, 0.0, 0.0, 1.0), march / MAX_DIST);
        renderImg[id.xy] = finalColor;
    } else renderImg[id.xy] = float4(0.1, 0.0, 0.15, 1.0);
}