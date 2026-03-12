
pub const RendererQueue = struct {};

pub const RendererEvent = union(enum) {
    addShader,
    addTexture,
    addBuffer,
    updateBuffer,
    updateWindowStates,
    toggleGpuProfiling,
    toggleUi,
};