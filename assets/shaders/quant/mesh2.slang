import Globals;

struct VertexOut {
    float4 pos : SV_Position;
    float3 color : COLOR0;
};

[[vk::binding(0, 0)]] ConstantBuffer<CameraData> heapCameraBuffers[];
[[vk::push_constant]] ConstantBuffer<PushConstants> pc;

static const uint SUBDIVISION_LEVEL = 9; 

float3 InterpolateFrustum(float3 uvw, float4 corners[8]) {
    float3 nearBottom = lerp(corners[0].xyz, corners[1].xyz, uvw.x);
    float3 nearTop    = lerp(corners[2].xyz, corners[3].xyz, uvw.x);
    float3 farBottom  = lerp(corners[4].xyz, corners[5].xyz, uvw.x);
    float3 farTop     = lerp(corners[6].xyz, corners[7].xyz, uvw.x);

    float3 nearFace = lerp(nearBottom, nearTop, uvw.y);
    float3 farFace  = lerp(farBottom, farTop, uvw.y);

    return lerp(nearFace, farFace, uvw.z);
}

[shader("mesh")]
[outputtopology("triangle")][numthreads(1, 1, 1)]
void main(
    uint3 groupId: SV_GroupID, 
    out vertices VertexOut verts[4], 
    out indices uint3 tris[2]
) {
    ConstantBuffer<CameraData> cam = heapCameraBuffers[pc.resources[0]];
    ConstantBuffer<CameraData> cullCam = heapCameraBuffers[pc.resources[1]];

    uint mortonCode = groupId.x;
    float3 uvwMin = float3(0.0, 0.0, 0.0);
    float3 uvwMax = float3(1.0, 1.0, 1.0);

    // Decode Morton Code exactly (Z -> X -> Y)
    for (uint i = 0; i < SUBDIVISION_LEVEL; i++) {
        uint axis = (i % 3 == 0) ? 2 : ((i % 3 == 1) ? 0 : 1);
        uint bit = (mortonCode >> (SUBDIVISION_LEVEL - 1 - i)) & 1;

        if (bit == 0) uvwMax[axis] = lerp(uvwMin[axis], uvwMax[axis], 0.5);
        else          uvwMin[axis] = lerp(uvwMin[axis], uvwMax[axis], 0.5);
    }

    uvwMin.z = max(uvwMin.z, 0.0005); // glitch fix

    SetMeshOutputCounts(4, 2);

    float3 cellColor = hashColor(groupId);

    // 4 corners of the FRONT FACE (Z = uvwMin.z)
    float3 quadUVW[4] = {
        float3(uvwMin.x, uvwMin.y, uvwMin.z), 
        float3(uvwMax.x, uvwMin.y, uvwMin.z),
        float3(uvwMin.x, uvwMax.y, uvwMin.z), 
        float3(uvwMax.x, uvwMax.y, uvwMin.z)
    };

    for (uint i = 0; i < 4; ++i) {
        float3 worldPos = InterpolateFrustum(quadUVW[i], cullCam.frustumCorners);
        verts[i].pos = mul(cam.viewProj, float4(worldPos, 1.0));
        verts[i].color = cellColor;
    }

    tris[0] = uint3(0, 1, 2);
    tris[1] = uint3(2, 1, 3);
}