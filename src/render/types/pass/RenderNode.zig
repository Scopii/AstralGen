const TexPassId = @import("../../../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../../../.configs/idConfig.zig").BufPassId;
const WindowId = @import("../../../.configs/idConfig.zig").WindowId;
const PassId = @import("../../../.configs/idConfig.zig").PassId;
const TexId = @import("../../../.configs/idConfig.zig").TexId;
const BufId = @import("../../../.configs/idConfig.zig").BufId;
const PassInstance = @import("PassInstance.zig").PassInstance;

pub const TexUnion = union(enum) {
    texName: []const u8, // Should be String?
    texPassId: TexPassId,
    texId: TexId,
};

pub const BufUnion = union(enum) {
    bufName: []const u8, // Should be String?
    bufPassId: BufPassId,
    bufId: BufId,
};

pub const RenderNode = union(enum) {
    blitNode: ViewportBlit,
    passNode: PassInstance,
    uiNode: UiNode,
    compositeNode: CompositeNode,
    clearBuffer: BufId,
    clearTexture: TexId,
    barrierBakeClears: void,
};

pub const CompositeNode = struct {
    name: []const u8, // Should be String
    pass: PassId,
    windowId: WindowId,
    srcTexUnion: TexUnion,
    viewWidth: u32,
    viewHeight: u32,
    viewOffsetX: i32,
    viewOffsetY: i32,
    opacity: f32,
    stretch: bool,
};

pub const UiNode = struct {
    name: []const u8, // Should be String
    windowId: WindowId,
    displayPos: [2]f32,
    displaySize: [2]f32,
    imguiVB: BufUnion,
    imguiIB: BufUnion,
    firstDrawIndex: u32,
    lastDrawIndex: u32,

    pub const UiDraw = struct {
        drawTex: TexUnion,
        clipRect: [4]f32,
        vtxOffset: i32,
        idxOffset: u32,
        elemCount: u32,
    };
};

pub const ViewportBlit = struct {
    name: []const u8, // Should be String
    pass: PassId,
    srcTexUnion: TexUnion,
    dstWindowId: WindowId,
    viewWidth: u32,
    viewHeight: u32,
    viewOffsetX: i32,
    viewOffsetY: i32,
};
