import Globals;

struct VertexOut {
    float4 pos : SV_Position;
    float3 color : COLOR0;
};

[[vk::binding(0, 0)]] ConstantBuffer<CameraData> heapCameraBuffers[];
[[vk::push_constant]] ConstantBuffer<PushConstants> pc;

static const uint SUBDIVISION_LEVEL = 9; 

// Helper to project the normalized 0..1 box into your physical camera frustum
float3 InterpolateFrustum(float3 uvw, float4 c[8]) {
    float3 nb = lerp(c[0].xyz, c[1].xyz, uvw.x); float3 nt = lerp(c[2].xyz, c[3].xyz, uvw.x);
    float3 fb = lerp(c[4].xyz, c[5].xyz, uvw.x); float3 ft = lerp(c[6].xyz, c[7].xyz, uvw.x);
    return lerp(lerp(nb, nt, uvw.y), lerp(fb, ft, uvw.y), uvw.z);
}

[shader("mesh")]
[outputtopology("line")][numthreads(1, 1, 1)]
void main(uint3 groupId: SV_GroupID, out vertices VertexOut verts[8], out indices uint2 lines[12]) {
    ConstantBuffer<CameraData> cam = heapCameraBuffers[pc.resources[0]];
    ConstantBuffer<CameraData> cullCam = heapCameraBuffers[pc.resources[1]];

    uint N = groupId.x;
    uint totalAllowedNodes = 1u << SUBDIVISION_LEVEL;

    // SAFETY: If Compute Shader dispatched too many workgroups kill them.
    // guarantees ONLY showing up to SUBDIVISION_LEVEL.
    if (N >= totalAllowedNodes) {
        SetMeshOutputCounts(0, 0);
        return;
    }

    if (N == 0) {
        // NODE 0: DRAW THE OUTER FRUSTUM
        SetMeshOutputCounts(8, 12);
        
        // Depth 0 is pure Green
        float3 color = float3(0.0, 1.0, 0.0); 

        float3 c[8] = {
            float3(0,0,0), float3(1,0,0), float3(0,1,0), float3(1,1,0),
            float3(0,0,1), float3(1,0,1), float3(0,1,1), float3(1,1,1)
        };
        for(int i=0; i<8; i++) {
            verts[i].pos = mul(cam.viewProj, float4(InterpolateFrustum(c[i], cullCam.frustumCorners), 1.0));
            verts[i].color = color;
        }
        
        uint2 l[12] = { uint2(0,1),uint2(1,3),uint2(3,2),uint2(2,0), uint2(4,5),uint2(5,7),uint2(7,6),uint2(6,4), uint2(0,4),uint2(1,5),uint2(2,6),uint2(3,7) };
        for(int j=0; j<12; j++) lines[j] = l[j];
        
    } else {
        // NODES 1+: DRAW THE INTERNAL SPLIT PLANES
        SetMeshOutputCounts(4, 4); // A slicing plane is 1 quad -> 4 lines

        // Find the Depth of this split based on binary MSB
        // N=1 -> Depth=1. N=2,3 -> Depth=2. N=4,5,6,7 -> Depth=3.
        uint splitDepth = firstbithigh(N) + 1; 
        uint parentDepth = splitDepth - 1;

        // Decode the PARENT Cell bounds that we are about to cut
        float3 uvwMin = float3(0.0, 0.0, 0.0);
        float3 uvwMax = float3(1.0, 1.0, 1.0);
        
        for (uint i = 0; i < parentDepth; i++) {
            uint axis = (i % 3 == 0) ? 2 : ((i % 3 == 1) ? 0 : 1); // Z, X, Y
            uint bit = (N >> (parentDepth - 1 - i)) & 1;
            if (bit == 0) uvwMax[axis] = lerp(uvwMin[axis], uvwMax[axis], 0.5);
            else          uvwMin[axis] = lerp(uvwMin[axis], uvwMax[axis], 0.5);
        }

        // Determine the Axis we are slicing right now
        uint splitAxis = (parentDepth % 3 == 0) ? 2 : ((parentDepth % 3 == 1) ? 0 : 1);
        float splitPos = lerp(uvwMin[splitAxis], uvwMax[splitAxis], 0.5);

        // Build the 4 corners of the slicing plane
        float3 p[4];
        if (splitAxis == 0) { // Slicing X (Vertical Plane down the middle)
            p[0] = float3(splitPos, uvwMin.y, uvwMin.z); p[1] = float3(splitPos, uvwMax.y, uvwMin.z);
            p[2] = float3(splitPos, uvwMax.y, uvwMax.z); p[3] = float3(splitPos, uvwMin.y, uvwMax.z);
        } else if (splitAxis == 1) { // Slicing Y (Horizontal Plane across the middle)
            p[0] = float3(uvwMin.x, splitPos, uvwMin.z); p[1] = float3(uvwMax.x, splitPos, uvwMin.z);
            p[2] = float3(uvwMax.x, splitPos, uvwMax.z); p[3] = float3(uvwMin.x, splitPos, uvwMax.z);
        } else { // Slicing Z (Depth Plane separating front from back)
            p[0] = float3(uvwMin.x, uvwMin.y, splitPos); p[1] = float3(uvwMax.x, uvwMin.y, splitPos);
            p[2] = float3(uvwMax.x, uvwMax.y, splitPos); p[3] = float3(uvwMin.x, uvwMax.y, splitPos);
        }

        // Color Gradient (Green -> Red based on which depth its at)
        float t = 0.0;
        if (SUBDIVISION_LEVEL > 0) {
            t = float(splitDepth) / float(SUBDIVISION_LEVEL);
        }
        // Green at t=0, Yellow at t=0.5, Red at t=1.0
        float3 splitColor = lerp(float3(0, 1, 0), float3(1, 0, 0), t); 

        // Emit 4 edges of the slice
        for(int i=0; i<4; i++) {
            verts[i].pos = mul(cam.viewProj, float4(InterpolateFrustum(p[i], cullCam.frustumCorners), 1.0));
            verts[i].color = splitColor;
        }

        lines[0] = uint2(0, 1); lines[1] = uint2(1, 2);
        lines[2] = uint2(2, 3); lines[3] = uint2(3, 0);
    }
}