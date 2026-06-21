const TextureEnum = @import("../../../frameBuild/enums.zig").TextureEnum;
const WindowId = @import("../../../window/Window.zig").Window.WindowId;
const PassId = @import("../../../frameBuild/components.zig").PassId;
const TexId = @import("../res/TextureMeta.zig").TextureMeta.TexId;
const BufId = @import("../res/BufferMeta.zig").BufferMeta.BufId;
const PassNode = @import("PassDef.zig").PassNode;

pub const RenderNode = union(enum) {
    viewportBlit: ViewportBlit,
    passNode: PassNode,
    uiNode: UiNode,
    compositeNode: CompositeNode,
    clearBuffer: BufId,
    clearTexture: TexId,
    barrierBakeClears: void,
};

pub const CompositeNode = struct {
    name: []const u8,
    pass: PassId,
    windowId: WindowId,
    srcTexEnum: ?TextureEnum = null,
    viewWidth: u32,
    viewHeight: u32,
    viewOffsetX: i32,
    viewOffsetY: i32,
    opacity: f32,
    stretch: bool,
};

pub const UiNode = struct {
    name: []const u8,
    windowId: WindowId,
    displayPos: [2]f32,
    displaySize: [2]f32,
    drawList: []const UiDraw,

    pub const UiDraw = struct {
        clipRect: [4]f32,
        texEnum: TextureEnum,
        vtxOffset: i32,
        idxOffset: u32,
        elemCount: u32,
    };
};

pub const ViewportBlit = struct {
    name: []const u8,
    pass: PassId,
    srcTexEnum: ?TextureEnum = null,
    dstWindowId: WindowId,
    viewWidth: u32,
    viewHeight: u32,
    viewOffsetX: i32,
    viewOffsetY: i32,
};
