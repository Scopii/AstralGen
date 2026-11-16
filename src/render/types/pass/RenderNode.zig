const TaskOrMeshIndirectExec = @import("../pass/PassDefinition.zig").TaskOrMeshIndirectExec;
const VertexIndexedExec = @import("../pass/PassDefinition.zig").VertexIndexedExec;
const TaskOrMeshExec = @import("../pass/PassDefinition.zig").TaskOrMeshExec;
const VertexAttribute = @import("VertexAttribute.zig").VertexAttribute;
const VertexBufferUse = @import("VertexBufferUse.zig").VertexBufferUse;
const TexPassId = @import("../../../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../../../.configs/idConfig.zig").BufPassId;
const RenderStateUnion = @import("RenderState.zig").RenderStateUnion;
const WindowId = @import("../../../.configs/idConfig.zig").WindowId;
const ShaderId = @import("../../../.configs/idConfig.zig").ShaderId;
const VertexExec = @import("../pass/PassDefinition.zig").VertexExec;
const IndexBufferUse = @import("IndexBufferUse.zig").IndexBufferUse;
const PassId = @import("../../../.configs/idConfig.zig").PassId;
const TextureState = @import("../res/Texture.zig").TextureState;
const QueryTyp = @import("../base/Cmd.zig").QueryPair.QueryTyp;
const TexId = @import("../../../.configs/idConfig.zig").TexId;
const BufId = @import("../../../.configs/idConfig.zig").BufId;
const BufferState = @import("../res/Buffer.zig").BufferState;
const ClearColor = @import("AttachmentUse.zig").ClearColor;
const ClearDepth = @import("AttachmentUse.zig").ClearDepth;
const String = @import("../../../globalHelper.zig").String;
const vhE = @import("../../help/Enums.zig");

pub const CompositeNode = struct {
    name: []const u8, // Should be String
    passId: PassId,
    windowId: WindowId,
    srcTexPassId: TexPassId,
    viewWidth: u32,
    viewHeight: u32,
    viewOffsetX: i32,
    viewOffsetY: i32,
    opacity: f32,
    stretch: bool,
};

pub const CompositeFill = struct {
    name: []const u8, // Should be String
    pass: PassId,
    windowId: WindowId,
    srcTexId: TexId,
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
    imguiVB: []const u8,
    imguiIB: []const u8,

    firstDrawIndex: u32,
    lastDrawIndex: u32,

    pub const UiDraw = struct {
        drawTex: []const u8,
        clipRect: [4]f32,
        vtxOffset: i32,
        idxOffset: u32,
        elemCount: u32,
    };
};

pub const UiNodeFill = struct {
    name: []const u8, // Should be String
    windowId: WindowId,
    displayPos: [2]f32,
    displaySize: [2]f32,
    imguiVB: BufId,
    imguiIB: BufId,

    firstDrawIndex: u32,
    lastDrawIndex: u32,

    pub const UiDrawFill = struct {
        drawTex: TexId,
        clipRect: [4]f32,
        vtxOffset: i32,
        idxOffset: u32,
        elemCount: u32,
    };
};

pub const RenderNodeIR = union(enum) {
    updateResourceStates: void,
    recordTransfers: void,
    clearBufIR: BufPassId,
    clearTexIR: TexPassId,
    passIR: PassId,
    compositeIR: CompositeNode,
    buildUi: void,
    present: void,
    syncPoint: void,
};

pub const BarrierState = struct {
    writeStage: u64 = 0,
    writeAccess: u64 = 0,
    readStages: u64 = 0,
    readAccess: u64 = 0,
};


pub const BarrierMask = struct {
    srcStage: u64 = 0,
    srcAccess: u64 = 0,
    dstStage: u64 = 0,
    dstAccess: u64 = 0,

    pub fn merge(self: *BarrierMask, mask: BarrierMask) void {
        self.srcStage |= mask.srcStage;
        self.srcAccess |= mask.srcAccess;
        self.dstStage |= mask.dstStage;
        self.dstAccess |= mask.dstAccess;
    }
};

pub const RenderNode = union(enum) {
    passPrint: String(30, "NO_PASS_NAME"),
    compositePrint: String(30, "NO_COMPOSITE_NAME"),
    uiPrint: String(30, "NO_UI_NAME"),

    recordTransfers: void,

    // Graph Commands
    clearBuffer: BufId,
    clearTexture: TexId,

    // Barrier Commands
    memBarrier: struct { mask: BarrierMask },
    bufBarrier: struct { bufId: BufId, mask: BarrierMask },
    texBarrier: struct { texId: TexId, mask: BarrierMask, oldLayout: vhE.ImageLayout, newLayout: vhE.ImageLayout },
    swapchainBarrier: struct { windowId: WindowId, mask: BarrierMask, oldLayout: vhE.ImageLayout, newLayout: vhE.ImageLayout },
    bakeBarriers: void,

    // Profiling Commands
    startTimer: struct { pipeStage: vhE.PipeStage, queryId: u8, name: String(30, "START_TIMER_NAME_MISSING"), typ: QueryTyp },
    endTimer: struct { pipeStage: vhE.PipeStage, queryId: u8 },
    startStats: String(30, "NO_START_STAT_NAME"),
    endStats: void,

    // Pass Commands
    setShader: ShaderId,
    bindShaders: void,

    setPushData: struct { startIndex: u32, len: u8, offset: u32 },
    setPushDataOutputExtent: struct { offset: u32 },
    setPushDataBufDesc: struct { bufId: BufId, size: u32, offset: u32 },
    setPushDataTexDesc: struct { texId: TexId, descTyp: vhE.TexDescriptor, size: u32, offset: u32 },
    bindPushData: void,

    dispatch: struct { groupX: u32, groupY: u32, groupZ: u32 },
    dispatchOutputTex: struct { groupX: u32, groupY: u32, groupZ: u32, texId: TexId },
    dispatchIndirect: struct { indirectBufId: BufId, indirectBufOffset: u64 = 0 },

    setOutputExtentSwapchain: WindowId,
    setOutputExtent: ?TexId,

    // Draw Commands
    beginRendering: void,

    setViewport: struct { x: f32, y: f32, width: f32, height: f32 },
    setViewportFromTex: TexId,
    setViewportFromOutput: void,
    setScissor: struct { x: f32, y: f32, width: f32, height: f32 },
    setScissorFromTex: TexId,
    setScissorFromOutput: void,

    setRenderStateUnion: RenderStateUnion,
    bindRenderState: void,

    setColorAttSwapchain: struct { windowId: WindowId, firstUse: bool },
    setColorAtt: struct { texId: TexId, clear: ?ClearColor },
    setDepthAtt: struct { texId: TexId, clear: ?ClearDepth },
    setStencilAtt: struct { texId: TexId, clear: ?ClearDepth },

    setIndexBuf: IndexBufferUse,
    bindIndexInput: void,

    setVertexBuf: VertexBufferUse,
    setVertexAttrib: VertexAttribute,
    bindVertexInput: void,

    drawVertex: VertexExec,
    drawVertexIndexed: VertexIndexedExec,

    drawTaskOrMesh: TaskOrMeshExec,
    drawTaskOrMeshIndirect: TaskOrMeshIndirectExec,

    endRendering: void,

    resetState: void,
};
