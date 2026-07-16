const TexPassId = @import("../../../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../../../.configs/idConfig.zig").BufPassId;
const WindowId = @import("../../../.configs/idConfig.zig").WindowId;
const ShaderId = @import("../../../.configs/idConfig.zig").ShaderId;
const PassId = @import("../../../.configs/idConfig.zig").PassId;
const TexId = @import("../../../.configs/idConfig.zig").TexId;
const BufId = @import("../../../.configs/idConfig.zig").BufId;
const PassInstance = @import("PassInstance.zig").PassInstance;
const String = @import("../../../globalHelper.zig").String;
const RenderState = @import("RenderState.zig").RenderState;
const RenderStateUnion = @import("RenderState.zig").RenderStateUnion;
const vhE = @import("../../help/Enums.zig");

const QueryTyp = @import("../base/Cmd.zig").QueryPair.QueryTyp;
const ClearColor = @import("AttachmentSlot.zig").AttachmentSlot.ClearColor;
const ClearDepth = @import("AttachmentSlot.zig").AttachmentSlot.ClearDepth;
const VertexAttribute = @import("VertexAttribute.zig").VertexAttribute;
const VertexBufferFill = @import("VertexBufferFill.zig").VertexBufferFill;
const IndexBufferFill = @import("IndexBufferFill.zig").IndexBufferFill;

pub const RenderNodeIR = union(enum) {
    blitIR: ViewportBlit, // Could be improved
    compositeIR: CompositeNode, // Could be improved
    passIR: PassId,
    clearBufIR: BufPassId,
    clearTexIR: TexPassId,
    barrierBakeClears: void,
};

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

// pub const UiPass = struct {
//     scissorX: f32,
//     scissorY: f32,
//     scissorWidth: f32,
//     scissorHeight: f32,

//     indexCount: u32,
//     instanceCount: u32,
//     firstIndex: u32,
//     vertexOffset: i32,
//     firstInstance: u32,

//     pushData: [128]u8,
//     pushDataByteLen: u8,

//     pass: PassInstance,
// };

pub const RenderNode = union(enum) {
    blitNode: ViewportBlit,
    // passNode: PassInstance,
    uiNode: UiNode,
    compositeNode: CompositeNode,

    // Graph Commands
    clearBuffer: BufId,
    clearTexture: TexId,
    barrierBakeClears: void,

    // Barrier Commands
    bufBarrier: struct { bufId: BufId, stage: vhE.PipeStage, access: vhE.PipeAccess },
    texBarrier: struct { texId: TexId, stage: vhE.PipeStage, access: vhE.PipeAccess, layout: vhE.ImageLayout },
    swapchainTargetBarrier: struct { windowId: WindowId, stage: vhE.PipeStage, access: vhE.PipeAccess, layout: vhE.ImageLayout },
    bakeBarriers: void,

    // Profiling Commands
    startTimer: struct { pipeStage: vhE.PipeStage, queryId: u8, name: String(30, "CMD_START_TIMER_MISSING") = .{}, typ: QueryTyp },
    endTimer: struct { pipeStage: vhE.PipeStage, queryId: u8 },

    startStats: struct { name: String(30, "CMD_START_STATS_MISSING") = .{} },
    endStats: void,

    // Pass Commands
    setShader: ShaderId,

    setPushData: struct { data: [128]u8, size: u32, offset: u32 },
    setPushDataOutputExtent: struct { offset: u32 },
    setPushDataBufDesc: struct { bufId: BufId, size: u32, offset: u32 },
    setPushDataTexDesc: struct { texId: TexId, descTyp: vhE.TexDescriptor, size: u32, offset: u32 },
    bindPushData: void,

    dispatch: struct { groupX: u32, groupY: u32, groupZ: u32 },
    dispatchImg: struct { groupX: u32, groupY: u32, groupZ: u32, img: TexId },
    dispatchIndirect: struct { indirectBuf: BufId, indirectBufOffset: u64 = 0 },

    setOutputExtentSwapchain: struct { windowId: WindowId },
    setOutputExtent: struct { mainOutput: ?TexId },

    bindShaders: void,

    // Draw Commands
    beginRendering: void,

    setViewport: struct { x: f32, y: f32, width: f32, height: f32 },
    setViewportFromTex: struct { texId: TexId },
    setViewportFromOutput: void,
    setScissor: struct { x: f32, y: f32, width: f32, height: f32 },
    setScissorFromTex: struct { texId: TexId },
    setScissorFromOutput: void,

    // setRenderState: RenderState,
    setRenderStateUnion: RenderStateUnion,
    bindRenderState: void,

    setColorAttSwapchain: struct { windowId: WindowId },
    setColorAtt: struct { texId: TexId, clear: ?ClearColor },
    setDepthAtt: struct { texId: TexId, clear: ?ClearDepth },
    setStencilAtt: struct { texId: TexId, clear: ?ClearDepth },

    setIndexBuf: struct { indexBuffer: IndexBufferFill },
    bindIndexInput: void,

    setVertexBuf: struct { vertexBuffer: VertexBufferFill },
    setVertexAttrib: struct { vertexAttribute: VertexAttribute },
    bindVertexInput: void,

    drawVertex: struct { vertexCount: u32, instanceCount: u32, firstVertex: u32, firstInstance: u32 },
    drawVertexIndexed: struct { indexCount: u32, instanceCount: u32, firstIndex: u32, vertexOffset: i32, firstInstance: u32 },

    drawTaskOrMesh: struct { groupX: u32, groupY: u32, groupZ: u32 },
    drawTaskOrMeshIndirect: struct { indirectBufId: BufId, offset: u64, drawCount: u32, stride: u32 },

    endRendering: void,

    resetState: void,
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
