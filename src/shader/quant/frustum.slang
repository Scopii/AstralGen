import Globals;

struct VertexOut {
    float4 pos : SV_Position;
    float3 color : COLOR0;
};

// near corners: 0-3, far corners: 4-7
// near corner n always corresponds to far corner n+4
static const uint2 nearEdges[4] = {
    uint2(0,1), uint2(1,3), uint2(3,2), uint2(2,0),
};

static const uint2 farEdges[4] = {
    uint2(4, 5), uint2(5, 7), uint2(7, 6), uint2(6, 4),
};

static const int SUBDIVISIONS = 20;
// lines: 4 near quad + 4 corner rays + 4*SUBDIVISIONS intermediate
// verts: lines * 2
static const int LINE_COUNT = 4 + 4 + 4 * SUBDIVISIONS + 4;
static const int VERT_COUNT = LINE_COUNT * 2;

[[vk::binding(0,0)]] ConstantBuffer<CameraData> heapCameraBuffers[];
[[vk::push_constant]] ConstantBuffer<PushConstants> pc;

[shader("mesh")]
[outputtopology("line")]
[numthreads(1,1,1)]
void main(out vertices VertexOut verts[VERT_COUNT], out indices uint2 lines[LINE_COUNT]) {
    ConstantBuffer<CameraData> cam = heapCameraBuffers[pc.resources[0]];

    uint vi = 0, li = 0;

    // near quad
    for (uint e = 0; e < 4; e++) {
        float3 a = cam.frustumCorners[nearEdges[e].x].xyz;
        float3 b = cam.frustumCorners[nearEdges[e].y].xyz;
        verts[vi].pos     = mul(cam.viewProj, float4(a, 1)); verts[vi].color   = float3(1,1,1);
        verts[vi+1].pos   = mul(cam.viewProj, float4(b, 1)); verts[vi+1].color = float3(1,1,1);
        lines[li++] = uint2(vi, vi+1);
        vi += 2;
    }

    // // far quad
    // for (uint e = 0; e < 4; e++) {
    //     float3 a = cam.frustumCorners[farEdges[e].x].xyz;
    //     float3 b = cam.frustumCorners[farEdges[e].y].xyz;
    //     verts[vi].pos = mul(cam.viewProj, float4(a, 1)); verts[vi].color = float3(1, 1, 1);
    //     verts[vi + 1].pos = mul(cam.viewProj, float4(b, 1)); verts[vi + 1].color = float3(1, 1, 1);
    //     lines[li++] = uint2(vi, vi + 1);
    //     vi += 2;
    // }

    // 4 corner rays (near corner n → far corner n+4)
    for (uint n = 0; n < 4; n++) {
        float3 a = cam.frustumCorners[n].xyz;
        float3 b = cam.frustumCorners[n+4].xyz;
        verts[vi].pos     = mul(cam.viewProj, float4(a, 1)); verts[vi].color   = float3(1,1,1);
        verts[vi+1].pos   = mul(cam.viewProj, float4(b, 1)); verts[vi+1].color = float3(1,1,1);
        lines[li++] = uint2(vi, vi+1);
        vi += 2;
    }

    // intermediate rays along each near edge, shooting to the lerped far edge
    for (uint e = 0; e < 4; e++) {
        uint na = nearEdges[e].x;
        uint nb = nearEdges[e].y;
        uint fa = na + 4; // corresponding far corner
        uint fb = nb + 4;

        for (int s = 1; s <= SUBDIVISIONS; s++) {
            float  t      = float(s) / float(SUBDIVISIONS + 1);
            float3 nearPt = lerp(cam.frustumCorners[na].xyz, cam.frustumCorners[nb].xyz, t);
            float3 farPt  = lerp(cam.frustumCorners[fa].xyz, cam.frustumCorners[fb].xyz, t);
            verts[vi].pos     = mul(cam.viewProj, float4(nearPt, 1)); verts[vi].color   = float3(1,0.0,0);
            verts[vi+1].pos   = mul(cam.viewProj, float4(farPt,  1)); verts[vi+1].color = float3(1,0.0,0);
            lines[li++] = uint2(vi, vi+1);
            vi += 2;
        }
    }

    SetMeshOutputCounts(vi, li);
}