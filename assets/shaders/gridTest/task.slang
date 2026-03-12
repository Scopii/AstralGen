struct TaskPayload {
    float3 baseOffset; // Global offset for whole grid
};

groupshared TaskPayload payload;

[shader("amplification")]
[numthreads(1, 1, 1)] 
void main() {
    payload.baseOffset = float3(-5, -5, 0);

    DispatchMesh(10, 10, 10, payload); 
}