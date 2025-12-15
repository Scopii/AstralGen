struct TaskPayload {
    float3 baseOffset; // Global offset for the whole grid
};

groupshared TaskPayload payload;

[shader("amplification")]
[numthreads(1, 1, 1)] 
void main() {
    // 1. Setup global data (Optional)
    payload.baseOffset = float3(-5, -5, 0); // Center the grid?

    // 2. Launch 1000 Mesh Shader Workgroups (10 * 10 * 10)
    // The hardware automatically assigns them IDs from (0,0,0) to (9,9,9)
    DispatchMesh(10, 10, 10, payload); 
}