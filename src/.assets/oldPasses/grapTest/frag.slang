import Globals;

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
[shader("fragment")]
float4 main(float4 pixelPos: SV_Position) : SV_Target {
    RWTexture2D<float4> renderImg = heapRWImages[pc.resources[2]];
    StructuredBuffer<Object> objectBuffer = heapObjectBuffers[pc.resources[0]];
    ConstantBuffer<CameraData> cam = heapCameraBuffers[pc.resources[1]];

    uint width = pc.width;
    uint height = pc.height;
    float2 renderDimensions = float2(width, height);
    float2 uv = (pixelPos.xy / renderDimensions) * 2.0 - 1.0;

    float3 camForward = normalize(cam.camDir.xyz);
    float3 camRight = normalize(cross(camForward, float3(0, 1, 0)));
    float3 camUp = normalize(cross(camRight, camForward));

    float focalLength = 1.0 / tan(radians(cam.camPosAndFov.w * 0.5));
    float aspectRatio = renderDimensions.x / renderDimensions.y;
    float3 rayDir = normalize(uv.x * camRight * aspectRatio - uv.y * camUp + focalLength * camForward);

    // Raymarching
    float march = 0.0;
    bool hit = false;
    float3 pos = float3(0, 0, 0);
    int hitIndex = -1; // Local var

    [loop]
    for (int step = 0; step < MAX_STEPS; step++) {
        pos = cam.camPosAndFov.xyz + rayDir * march;
        MapResult res = map(pos, objectBuffer);

        if (res.dist < MIN_DIST) {
            hit = true;
            hitIndex = res.index; // Capture index safely
            break;
        }
        march += res.dist;
        if (march > MAX_DIST) break;
    }

    // Output
    if (hit && hitIndex != -1) {
        float3 normal = getNormal(pos, objectBuffer);
        float3 lightDir = normalize(float3(1.0, 1.0, -1.0));
        float lighting = max(dot(normal, lightDir), 0.1);

        Object hitObj = objectBuffer[hitIndex];

        // Unpack color
        float3 surfaceColor = hitObj.colorAndSdf.xyz;

        return lerp(float4(surfaceColor * lighting, 1.0), float4(0.0, 0.0, 0.0, 1.0), march / MAX_DIST);
    } else return float4(0.1, 0.0, 0.0, 1.0);
}