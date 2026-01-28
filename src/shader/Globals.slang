module Globals;

//Types

public struct ReadbackData {
    public float runtime;
    public float deltaTime;
    public uint width;
    public uint height;
}

public struct Object {
    public float posX;
    public float posY;
    public float posZ;
    public float size;
    public float colorR;
    public float colorG;
    public float colorB;
    public uint sdfId;
    public uint4 _padding; 
};

public struct CameraData {
    public float4x4 viewProj;
    public float4 camPosAndFov;
    public float4 camDir;
};

public struct Resource {
    public uint index;
    public uint count;
};

public struct PushConstants {
    public float runtime;
    public float deltaTime;
    public uint width;
    public uint height;
    public Resource resources[14];
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
