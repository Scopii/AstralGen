
struct Object {
    float posX; float posY; float posZ; float size;     
    float colorR; float colorG; float colorB; uint sdfId; 
    uint4 _padding; 
};

struct PushConstants {
    float4x4 viewProj;
    float4 camPosAndFov;
    float4 camDir;
    float runtime;
    uint renderImgIdx;
    uint objectBufCount;
    uint objectBufIdx;
};

[[vk::binding(0, 0)]] RWTexture2D<float4> globalImages[];
[[vk::binding(1, 0)]] StructuredBuffer<Object> globalBuffers[];
[[vk::push_constant]] ConstantBuffer<PushConstants> pc;

// Marching Constants
static const int MAX_STEPS = 512;
static const float MIN_DIST = 0.001;
static const float MAX_DIST = 200.0;
// Other Constants
static const float EPSILON = 0.001;


// SDFs
float sdSphere(float3 pos, float radius) { 
    return length(pos) - radius; 
}
float sdBox(float3 p, float3 b) {
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}
float sdTorus(float3 p, float2 t) {
    float2 q = float2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}
// Ray March Operations
float3 opRep(float3 x, float3 y) {
    return x - y * floor(x / y);
}

struct MapResult {
    float dist;
    int index;
};

MapResult map(float3 pos, StructuredBuffer<Object> objectBuffer) {
    float closestDist = MAX_DIST;
    int closestIndex = -1;

    // Loop over the Object Buffer
    for (uint i = 0; i < pc.objectBufCount; i++) {
        // 2. Read from that specific buffer
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
[shader("fragment")]
float4 main(float4 pixelPos: SV_Position) : SV_Target {
    StructuredBuffer<Object> objectBuffer = globalBuffers[pc.objectBufIdx];

    uint width, height;
    globalImages[pc.renderImgIdx].GetDimensions(width, height);
    float2 renderDimensions = float2(width, height);
    float2 uv = (pixelPos.xy / renderDimensions) * 2.0 - 1.0;

    float3 camForward = normalize(pc.camDir.xyz);
    float3 camRight = normalize(cross(camForward, float3(0, 1, 0)));
    float3 camUp = normalize(cross(camRight, camForward));

    float focalLength = 1.0 / tan(radians(pc.camPosAndFov.w * 0.5));
    float aspectRatio = renderDimensions.x / renderDimensions.y;
    float3 rayDir = normalize(uv.x * camRight * aspectRatio - uv.y * camUp + focalLength * camForward);

    // Raymarching
    float march = 0.0;
    bool hit = false;
    float3 pos = float3(0, 0, 0);
    int hitIndex = -1; // Local var

    [loop]
    for (int step = 0; step < MAX_STEPS; step++) {
        pos = pc.camPosAndFov.xyz + rayDir * march;
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
        float3 lightDirection = normalize(float3(1.0, 1.0, -1.0));
        float lighting = max(dot(normal, lightDirection), 0.1);

        Object hitObj = objectBuffer[hitIndex];
        float3 objColor = float3(hitObj.colorR, hitObj.colorG, hitObj.colorB);

        return lerp(float4(objColor * lighting, 1.0), float4(0.0, 0.0, 0.0, 1.0), march / MAX_DIST);
    } else return float4(0.1, 0.0, 0.0, 1.0);
}