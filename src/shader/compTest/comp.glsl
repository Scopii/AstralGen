#version 460
#extension GL_EXT_shader_image_load_formatted : require
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_nonuniform_qualifier : require

layout (local_size_x = 8, local_size_y = 8) in; // Work Group

layout(set = 0, binding = 0, rgba16f) uniform image2D globalImages[]; // Descriptor Layout 1

struct Object {
    float posX; float posY; float posZ; float size;     
    float colorR; float colorG; float colorB; uint sdfId;     
    vec4 padding2;
};
layout(set = 0, binding = 1, std430) readonly buffer ObjectBuffer { // Descriptor Layout 2
    Object objects[];
} objectBuffer;

// Push Constant
layout(push_constant, std430) uniform PushConstants {
    vec4 camPosAndFov;
    vec4 camDir;
    float runtime;
    uint dataCount;
    uint outputImageIndex;
} pc;

// Marching constants
const int MAX_STEPS = 512;
const float MIN_DIST = 0.001;
const float MAX_DIST = 200.0;
// Other Constants
const float EPSILON = 0.001;

// SDFs
float sdSphere(vec3 pos, float radius) { 
    return length(pos) - radius; 
}
float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}
float sdTorus(vec3 p, vec2 t) {
    vec2 q = vec2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}
float sdCylinder(vec3 p, vec2 h) {
    vec2 d = abs(vec2(length(p.xz), p.y)) - h;
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}
// Ray March Operations
vec3 opRep(vec3 pos, vec3 spacing) { 
    return mod(pos + 0.5 * spacing, spacing) - 0.5 * spacing; 
}

int closestObjectIndex = -1; //Global state for coloring

float map(vec3 pos) {
    float closestDist = MAX_DIST;

    // Loop Over Object Buffer
    for (int i = 0; i < pc.dataCount; i++) {
        Object obj = objectBuffer.objects[i]; 
        vec3 objPos = vec3(obj.posX, obj.posY, obj.posZ);
        
        float dist;
        if (obj.sdfId == 0) {
            dist = sdSphere(pos - objPos, obj.size);
        } else if (obj.sdfId == 1) {
            dist = sdBox(pos - objPos, vec3(obj.size));
        } else {
            dist = sdTorus(pos - objPos, vec2(obj.size, obj.size));
        }
        
        if (dist < closestDist) {
            closestDist = dist;
            closestObjectIndex = i;
        }
    }
    return closestDist;
}

// Normal Functions
vec3 getNormal(vec3 pos) {
    vec3 n = vec3(
        map(pos + vec3(EPSILON, 0, 0)) - map(pos - vec3(EPSILON, 0, 0)),
        map(pos + vec3(0, EPSILON, 0)) - map(pos - vec3(0, EPSILON, 0)),
        map(pos + vec3(0, 0, EPSILON)) - map(pos - vec3(0, 0, EPSILON))
    );
    return normalize(n);
}

// SHADER
void main() {
    uint renderImgIdx = pc.outputImageIndex; 
    vec2 renderDimensions = vec2(imageSize(globalImages[nonuniformEXT(renderImgIdx)]));

    // Bounds check (because group size is 8x8)
    if (gl_GlobalInvocationID.x >= renderDimensions.x || gl_GlobalInvocationID.y >= renderDimensions.y) return;
    
    vec2 uv = (vec2(gl_GlobalInvocationID.xy) / renderDimensions) * 2.0 - 1.0;

    vec3 camForward = normalize(pc.camDir.xyz);
    vec3 camRight = normalize(cross(vec3(0, 1, 0), camForward));
    vec3 camUp = normalize(cross(camForward, camRight));

    float focalLength = 1.0 / tan(radians(pc.camPosAndFov.w * 0.5));
    float aspectRatio = renderDimensions.x / renderDimensions.y;
    vec3 rayDirection = normalize(uv.x * camRight * aspectRatio - uv.y * camUp + focalLength * camForward);
    
    // Raymarching
    float march = 0.0;
    bool hit = false;
    vec3 pos = vec3(0, 0, 0);
    
    for(int step = 0; step < MAX_STEPS; step++) {
        pos = pc.camPosAndFov.xyz + rayDirection * march;
        float closest = map(pos);

        if(closest < MIN_DIST) {
            hit = true;
            break;
        }
        march += closest;
        if(march > MAX_DIST) break;
    }
    
    if(hit) {
        vec3 normal = getNormal(pos);
        vec3 lightDirection = normalize(vec3(1.0, 1.0, -1.0));
        float lighting = max(dot(normal, lightDirection), 0.1);

        Object hitObj = objectBuffer.objects[closestObjectIndex];
        vec3 objColor = vec3(hitObj.colorR, hitObj.colorG, hitObj.colorB);
        
        imageStore(globalImages[nonuniformEXT(renderImgIdx)], ivec2(gl_GlobalInvocationID.xy), mix(vec4(objColor * lighting, 1.0), vec4(0.0, 0.0, 0.0, 1.0), march / MAX_DIST));
    } else {
        imageStore(globalImages[nonuniformEXT(renderImgIdx)], ivec2(gl_GlobalInvocationID.xy), vec4(0.1, 0.0, 0.15, 1.0));
    }
}