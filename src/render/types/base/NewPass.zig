const ShaderId = @import("../../../shader/ShaderSys.zig").ShaderId;
const RenderState = @import("../base/RenderState.zig").RenderState;
const TextureMeta = @import("../res/TextureMeta.zig").TextureMeta;
const BufferMeta = @import("../res/BufferMeta.zig").BufferMeta;
const Texture = @import("../res/Texture.zig").Texture;
const Buffer = @import("../res/Buffer.zig").Buffer;
const vhE = @import("../../help/Enums.zig");
const TexId = TextureMeta.TexId;
const Pass = @import("Pass.zig").Pass;
const sc = @import("../../../.configs/shaderConfig.zig");
const rc = @import("../../../.configs/renderConfig.zig");

pub const PassDef = struct {
    name: []const u8,
    shaderIds: []const ShaderId,

    typ: enum { compute, graphics, taskOrMesh, taskOrMeshIndirect },

    // Compute/Mesh/Task
    workgroups: ?struct { x: u32, y: u32, z: u32 } = null,

    // Graphics
    mainTexId: ?TextureMeta.TexId = null,
    indirectBufId: ?BufferMeta.BufId = null,
    colorAtt: []const AttachmentSlot = &.{},
    depthAtt: ?AttachmentSlot = null,
    stencilAtt: ?AttachmentSlot = null,
    renderState: RenderState = .{},

    bufDef: []const BufferDef = &.{},
    texDef: []const TextureDef = &.{},

    pushConstants: type,
};

pub const mainCull = PassDef{
    .name = "MainCull",
    .shaderIds = &.{ sc.cullTestMesh.id, sc.cullTestFrag.id },

    .typ = .taskOrMeshIndirect,
    .indirectBufId = rc.indirectSB.id,
    .workgroups = .{ .x = 1, .y = 1, .z = 1 },

    .mainTexId = rc.mainTex.id,
    .colorAtt = &.{AttachmentDef{ .stage = .ColorAtt, .access = .ColorAttReadWrite, .layout = .Attachment, .clear = true }},
    .depthAtt = AttachmentDef{ .stage = .EarlyFragTest, .access = .DepthStencilWrite, .layout = .Attachment, .clear = true },
    .stencilAtt = null,

    .bufUses = &.{
        BufferDef{ .stage = .DrawIndirect, .access = .IndirectRead },
        BufferDef{ .stage = .FragShader, .access = .ShaderRead },
        BufferDef{ .stage = .FragShader, .access = .ShaderRead },
    },
    .texUses = &.{},

    // .pushConstants = struct {
    //     indirectBuffer: BufferMeta.BufId,
    //     camera1Buffer: BufferMeta.BufId,
    //     camera2Buffer: BufferMeta.BufId,
    // },

    // pushConstants: *PushConstants,

    // pub const PushConstants = struct {
    //     cameraBuf1 = BufDef,
    //     cameraBuf2 = BufDef,
    //     storageTex = TexDef,
    // };
};

pub const PassUsage = struct {
    name: []const u8,
    pass: PassDef = mainCull,

    colAttSlot: []const AttachmentDef = &.{},
    depthAttSlot: ?AttachmentDef = null,
    stencilAttSlot: ?AttachmentDef = null,

    bufSlot: []const BufferSlot = &.{},
    texSlot: []const TextureSlot = &.{},
};

pub const mainCullUsage = PassUsage{
    .name = "MainCull Usage1",
    .pass = mainCull,
    .colAttSlot = &.{rc.mainTex.id},
    .depthAttSlot = rc.mainDepthTex.id,
    .bufSlot = &.{
        rc.indirectSB.id,
        rc.camUB.id,
        rc.cam2UB.id,
    },
};

pub const AttachmentDef = struct {
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    layout: vhE.ImageLayout = .General,
    clear: bool,
};

pub const AttachmentSlot = struct {
    texId: TextureMeta.TexId,
};

pub const TextureDef = struct {
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    layout: vhE.ImageLayout = .General,
    shaderSlot: ?u32 = null,
};

pub const TextureSlot = struct {
    texId: TextureMeta.TexId,
};

pub const BufferDef = struct {
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    shaderSlot: ?u32 = null,
};

pub const BufferSlot = struct {
    bufId: BufferMeta.BufId,
};
