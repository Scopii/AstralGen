
struct Object {
    float posX; float posY; float posZ; float size;
    float colorR; float colorG; float colorB; uint sdfId;
    uint4 _padding;
};

struct PushConstants {
    float4 camPosAndFov;
    float4 camDir;
    float runtime;
    uint dataCount;
    uint outputImageIndex;
};

[[vk::binding(0, 0)]] RWTexture2D<float4> globalImages[]; // Descriptor Layout 1
[[vk::binding(1, 0)]] StructuredBuffer<Object> objectBuffer; // Descriptor Layout 2
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

static int closestObjectIndex = -1; //Global state for coloring

float map(float3 pos) {
    float closestDist = MAX_DIST;

    // Loop over the Object Buffer
    for (uint i = 0; i < pc.dataCount; i++) {
        Object obj = objectBuffer[i];
        float3 objPos = float3(obj.posX, obj.posY, obj.posZ);

        float dist = MAX_DIST;
        if (obj.sdfId == 0) {
            dist = sdSphere(pos - objPos, obj.size);
        } else if (obj.sdfId == 1) {
            dist = sdBox(pos - objPos, float3(obj.size, obj.size, obj.size));
        } else {
            dist = sdTorus(pos - objPos, float2(obj.size, obj.size));
        }

        if (dist < closestDist) {
            closestDist = dist;
            closestObjectIndex = i;
        }
    }
    return closestDist;
}

// Normal Functions
float3 getNormal(float3 pos) {
    return normalize(float3(
        map(pos + float3(EPSILON, 0, 0)) - map(pos - float3(EPSILON, 0, 0)),
        map(pos + float3(0, EPSILON, 0)) - map(pos - float3(0, EPSILON, 0)),
        map(pos + float3(0, 0, EPSILON)) - map(pos - float3(0, 0, EPSILON))
    ));
}

// SHADER
float4 main(float4 pixelPos: SV_Position) : SV_Target {
    uint width, height;
    globalImages[pc.outputImageIndex].GetDimensions(width, height);
    float2 renderDimensions = float2(width, height);
    float2 uv = (pixelPos.xy / renderDimensions) * 2.0 - 1.0;

    float3 camForward = normalize(pc.camDir.xyz);
    float3 camRight = normalize(cross(float3(0, 1, 0), camForward));
    float3 camUp = normalize(cross(camForward, camRight));

    float focalLength = 1.0 / tan(radians(pc.camPosAndFov.w * 0.5));
    float aspectRatio = renderDimensions.x / renderDimensions.y;
    float3 rayDir = normalize(uv.x * camRight * aspectRatio - uv.y * camUp + focalLength * camForward);

    // Raymarching
    float march = 0.0;
    bool hit = false;
    float3 pos = float3(0, 0, 0);

    [loop]
    for (int step = 0; step < MAX_STEPS; step++) {
        pos = pc.camPosAndFov.xyz + rayDir * march;
        float closest = map(pos);

        if (closest < MIN_DIST) {
            hit = true;
            break;
        }
        march += closest;
        if (march > MAX_DIST) break;
    }

    // Output
    if (hit) {
        float3 normal = getNormal(pos);
        float3 lightDirection = normalize(float3(1.0, 1.0, -1.0));
        float lighting = max(dot(normal, lightDirection), 0.1);

        Object hitObj = objectBuffer[closestObjectIndex];
        float3 objColor = float3(hitObj.colorR, hitObj.colorG, hitObj.colorB);

        return lerp(float4(objColor * lighting, 1.0), float4(0.0, 0.0, 0.0, 1.0), march / MAX_DIST);
    } else return float4(0.05, 0.04, 0.05, 1.0);
}