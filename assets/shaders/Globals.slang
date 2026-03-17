module Globals;

//Types

public struct ReadbackData {
    public float runtime;
    public float deltaTime;
    public uint width;
    public uint height;
}

public struct Object {
    public float4 posAndSize;
    public float4 colorAndSdf;
};

public struct CameraData {
    public float4x4 viewProj;
    public float4 camPosAndFov;
    public float4 camDir;
    public float4 frustumCorners[8];
    public float4 frustumPlanes[6]; // left,right,bottom,top,near,far
};

public struct PushConstants {
    public float runtime;
    public float deltaTime;
    public uint width;
    public uint height;
    public uint resources[14];
};

public struct IndirectCommand {
    public uint groupX;
    public uint groupY;
    public uint groupZ;
};

public struct MapResult {
    public float dist;
    public int index;
};

// SDFs

public float sdSphere(float3 pos, float radius) {
    return length(pos) - radius;
}

public float sdBox(float3 p, float3 b) {
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

public float sdTorus(float3 p, float2 t) {
    float2 q = float2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// Ray March Operations
public float3 opRep(float3 x, float3 y) {
    return x - y * floor(x / y);
}

public float3 hashColor(uint3 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    v ^= v >> 16u;
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    return float3(v) * (1.0 / float(0xffffffffu));
}
