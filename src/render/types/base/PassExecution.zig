const ShaderId = @import("../../../shader/ShaderSys.zig").ShaderId;
const RenderState = @import("../base/RenderState.zig").RenderState;
const TextureMeta = @import("../res/TextureMeta.zig").TextureMeta;
const BufferMeta = @import("../res/BufferMeta.zig").BufferMeta;
const Texture = @import("../res/Texture.zig").Texture;
const Buffer = @import("../res/Buffer.zig").Buffer;
const vhE = @import("../../help/Enums.zig");
const TexId = TextureMeta.TexId;

pub const TargetAction = enum { clear, load };

pub const RenderTarget = struct {
    texId: TexId,
    action: TargetAction,
};

pub const PassExecution = struct {
    name: []const u8,
    shaders: []const ShaderId,

    // Dependencies for automatic Vulkan barriers
    readBuffers: []const BufferMeta.BufId,
    readTextures: []const TextureMeta.TexId,
    writeTextures: []const TextureMeta.TexId,

    // Render Targets for Graphics Passes
    colorTargets: []const RenderTarget,
    depthTarget: ?RenderTarget,

    renderState: RenderState,

    // If true, the graph will call Dispatch. If false, it will call Draw.
    isCompute: bool,
    dispatchX: u32,
    dispatchY: u32,
    dispatchZ: u32,

    vertexCount: u32,

    // The logical screen coordinates for your Scissor and Viewport
    viewportX: f32,
    viewportY: f32,
    viewportW: f32,
    viewportH: f32,

    // The raw bytes of your bindless integer IDs and viewport dimensions
    pushDataBytes: []const u8,
};

pub const RayMarchData = extern struct {
    objectBufferId: u32,
    cameraBufferId: u32,
    renderImgId: u32,
    renderWidth: u32,
    renderHeight: u32,
    runTime: f32,
};
