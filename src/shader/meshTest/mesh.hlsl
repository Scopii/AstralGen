
struct VertexOut {
    float4 pos : SV_Position;
    float3 color : COLOR0; // Maps to Location 0
};
[outputtopology("triangle")]
[numthreads(1, 1, 1)] // workgroup
void main(
    // Output Arrays
    out vertices VertexOut verts[3],
    out indices uint3 tris[1]
) {
    SetMeshOutputCounts(3, 1); // Output for this Workgroup: 3 vertices, 1 triangle

    // Vertex 1
    verts[0].pos = float4(-1.0, -1.0, 0.0, 1.0);
    verts[0].color = float3(1.0, 0.0, 0.0); // Red
    // Vertex 2
    verts[1].pos = float4(3.0, -1.0, 0.0, 1.0);
    verts[1].color = float3(0.0, 1.0, 0.0); // Green
    // Vertex 3
    verts[2].pos = float4(-1.0, 3.0, 0.0, 1.0);
    verts[2].color = float3(0.0, 0.0, 1.0); // Blue

    tris[0] = uint3(0, 1, 2);
}