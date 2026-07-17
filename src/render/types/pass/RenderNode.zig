const RenderStateUnion = @import("RenderState.zig").RenderStateUnion;
const TexPassId = @import("../../../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../../../.configs/idConfig.zig").BufPassId;
const WindowId = @import("../../../.configs/idConfig.zig").WindowId;
const ShaderId = @import("../../../.configs/idConfig.zig").ShaderId;
const PassId = @import("../../../.configs/idConfig.zig").PassId;
const TexId = @import("../../../.configs/idConfig.zig").TexId;
const BufId = @import("../../../.configs/idConfig.zig").BufId;
const String = @import("../../../globalHelper.zig").String;
const vhE = @import("../../help/Enums.zig");

const QueryTyp = @import("../base/Cmd.zig").QueryPair.QueryTyp;
const ClearColor = @import("AttachmentUse.zig").ClearColor;
const ClearDepth = @import("AttachmentUse.zig").ClearDepth;
const VertexAttribute = @import("VertexAttribute.zig").VertexAttribute;
const VertexBufferFill = @import("VertexBufferUse.zig").VertexBufferFill;
const IndexBufferFill = @import("IndexBufferUse.zig").IndexBufferFill;

const TaskOrMeshIndirectExec = @import("../pass/PassDefinition.zig").TaskOrMeshIndirectExec;
const VertexIndexedExec = @import("../pass/PassDefinition.zig").VertexIndexedExec;
const TaskOrMeshExec = @import("../pass/PassDefinition.zig").TaskOrMeshExec;
const VertexExec = @import("../pass/PassDefinition.zig").VertexExec;

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

pub const RenderNodeIR = union(enum) {
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

pub const RenderNode = union(enum) {
    passPrint: String(30, "NO_PASS_NAME"),
    compositePrint: String(30, "NO_COMPOSITE_NAME"),
    uiPrint: String(30, "NO_UI_NAME"),

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

    setColorAttSwapchain: WindowId,
    setColorAtt: struct { texId: TexId, clear: ?ClearColor },
    setDepthAtt: struct { texId: TexId, clear: ?ClearDepth },
    setStencilAtt: struct { texId: TexId, clear: ?ClearDepth },

    setIndexBuf: IndexBufferFill,
    bindIndexInput: void,

    setVertexBuf: VertexBufferFill,
    setVertexAttrib: VertexAttribute,
    bindVertexInput: void,

    drawVertex: VertexExec,
    drawVertexIndexed: VertexIndexedExec,

    drawTaskOrMesh: TaskOrMeshExec,
    drawTaskOrMeshIndirect: TaskOrMeshIndirectExec,

    endRendering: void,

    resetState: void,
};
