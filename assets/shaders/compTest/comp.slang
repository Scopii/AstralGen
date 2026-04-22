import Globals;

[[vk::constant_id(0)]] const uint THREAD_X = 8;
[[vk::constant_id(1)]] const uint THREAD_Y = 8;
[[vk::constant_id(2)]] const uint THREAD_Z = 1;

// Images
[[vk::binding(0, 0)]] RWTexture2D<float4> heapRWImages[];
[[vk::binding(0, 0)]] Texture2D<float4> heapSampledImages[];
// Buffers
[[vk::binding(0, 0)]] StructuredBuffer<Object> heapObjectBuffers[];
[[vk::binding(0, 0)]] ConstantBuffer<CameraData> heapCameraBuffers[];
[[vk::binding(0, 0)]] RWStructuredBuffer<IndirectCommand> heapIndirectBuffers[];

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

    uint objectCount = objectBuffer.getCount();

    for (uint i = 0; i < objectCount; i++) {
        Object obj = objectBuffer[i];

        // Unpack the data exactly how Zig packed it
        float3 objPos = obj.posAndSize.xyz;
        float objSize = obj.posAndSize.w;
        uint sdfId = (uint)obj.colorAndSdf.w;

        float dist = MAX_DIST;
        if (sdfId == 0) dist = sdSphere(pos - objPos, objSize);
        else if (sdfId == 1) dist = sdBox(pos - objPos, float3(objSize));
        // A torus needs an inner and outer radius, so doing float2(size, size) makes a blob.
        // Doing size * 0.25 makes a proper donut shape!
        else dist = sdTorus(pos - objPos, float2(objSize, objSize * 0.25));

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
[numthreads(THREAD_X, THREAD_Y, THREAD_Z)]
void main(uint3 id: SV_DispatchThreadID) {
    // RWStructuredBuffer<ReadbackData> readback = heapReadbackBuffers[pc.resources[3]];
    // readback[0].runtime = pc.runtime;
    // readback[0].deltaTime = pc.deltaTime;
    // readback[0].width = pc.width;
    // readback[0].height = pc.height;

    RWTexture2D<float4> renderImg = heapRWImages[pc.resources[2]];
    StructuredBuffer<Object> objectBuffer = heapObjectBuffers[pc.resources[0]];
    ConstantBuffer<CameraData> cam = heapCameraBuffers[pc.resources[1]];

    Texture2D<float4> debugTex = heapSampledImages[pc.resources[4]];

    // Bounds check (because group size is 8x8)
    uint renderWidth = pc.width;
    uint renderHeight = pc.height;
    if (id.x >= renderWidth || id.y >= renderHeight) return;

    float2 uv = (float2(id.xy) / float2(renderWidth, renderHeight)) * 2.0 - 1.0;

    float3 camForward = normalize(cam.camDirAndAspectRatio.xyz);
    float3 camRight = normalize(cross(camForward, float3(0, 1, 0)));
    float3 camUp = normalize(cross(camRight, camForward));

    float focalLength = 1.0 / tan(radians(cam.camPosAndFov.w * 0.5));
    float aspectRatio = float(renderWidth) / float(renderHeight);
    // float aspectRatio = cam.camDirAndAspectRatio.w;
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
            hitIndex = result.index; 
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
        float3 surfaceColor = hitObj.colorAndSdf.xyz;

        // ----- READ THE TEXTURE -----
        // Convert UV (-1 to 1) -> (0 to 1) -> (0 to 255 pixels)
        float2 texCoord01 = uv * 0.5 + 0.5;
        uint2 texCoord = uint2(texCoord01 * 256.0) % 256;

        // Use .Load(int3(x, y, mip_level))
        float4 dbgColor = debugTex.Load(int3(texCoord, 0));
        // ----------------------------

        float4 finalColor = lerp(float4(surfaceColor * lighting, 1.0), float4(0.0, 0.0, 0.0, 1.0), march / MAX_DIST);

        renderImg[id.xy] = finalColor * dbgColor;
    } else {
        renderImg[id.xy] = float4(0.1, 0.0, 0.15, 1.0);
    }
}