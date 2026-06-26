const TexDesc = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const TexInf = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexInf;
const TexId = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexId;
const BufDesc = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const BufInf = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufInf;
const BufId = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufId;
pub const pe = @import("enums.zig");

const IdAdvanced = @import("../globalHelper.zig").IdAdvanced;
const Id = @import("../globalHelper.zig").Id;

pub const BufPassId = Id(u16, .BufPassId);
pub const TexPassId = Id(u16, .TexPassId);
pub const PassId = Id(u16, .PassId);

// pub const TexPassId = IdAdvanced(u16, .TexPassId, &.{
//     .{ .RayMarchInputTex, null },
//     .{ .GridTex, null },
//     .{ .GridDepthTex, null },
//     .{ .DebugGridInputTex, null },
//     .{ .DebugGridOutputTex, null },
//     .{ .DebugGridDepthTex, null },
//     .{ .DebugGridDepthOutputTex, null },
//     .{ .PlaneTex, null },
//     .{ .PlaneDepthTex, null },
//     .{ .DebugPlaneInputTex, null },
//     .{ .DebugPlaneOutputTex, null },
//     .{ .DebugPlaneOutputFrustumViewTex, null },
//     .{ .DebugPlaneDepthTex, null },
//     .{ .DepthViewTex, null },
//     .{ .TestTileTex, null },
//     .{ .ImguiFontTex, null },
//     // .{ .Swapchain, null },
// });

pub const TextureLink = struct {
    in: TexPassId,
    out: ?TexPassId = null,
};

pub const BufferLink = struct {
    in: BufPassId,
    out: ?BufPassId = null,
};

pub const TextureStringLink = struct {
    in: []const u8,
    out: ?[]const u8 = null,
};

pub const BufferStringLink = struct {
    in: []const u8,
    out: ?[]const u8 = null,
};

pub const TextureAccess = struct {
    pass: PassId,
    texInput: TexPassId,
    texOutput: ?TexPassId,
    access: enum { write, read },
};

pub const BufferAccess = struct {
    pass: PassId,
    bufInput: BufPassId,
    bufOutput: ?BufPassId,
    access: enum { write, read },
};

pub const TextureDependancy = struct {
    tex: TexPassId,
    predecessor: PassId,
    successor: PassId,
};

pub const BufferDependancy = struct {
    buf: BufPassId,
    predecessor: PassId,
    successor: PassId,
};

pub const GraphNode = struct {
    level: u16,
    pass: PassId,
};

pub const TextureLifetime = struct {
    tex: TexPassId,
    earliest: u16,
    latest: u16,
};

pub const BufferLifetime = struct {
    buf: BufPassId,
    earliest: u16,
    latest: u16,
};

pub const BufGroupLifetime = struct {
    rootBuf: BufPassId,
    earliest: u16,
    latest: u16,
};

pub const TexGroupLifetime = struct {
    rootTex: TexPassId,
    earliest: u16,
    latest: u16,
};

pub const BufLevelLifetime = struct {
    buf: BufPassId,
    firstLevel: u16,
    lastLevel: u16,
};

pub const TexLevelLifetime = struct {
    tex: TexPassId,
    firstLevel: u16,
    lastLevel: u16,
};

pub const BufferGroup = struct {
    rootPass: PassId,
    rootBuf: BufPassId,
    startMapIndex: u16,
    endMapIndex: u16,
    bufDesc: BufDesc,
};

pub const TextureGroup = struct {
    rootPass: PassId,
    rootTex: TexPassId,
    startMapIndex: u16,
    endMapIndex: u16,
    texDesc: TexDesc,
};

pub const BufGroupChange = struct {
    rootBuf: BufPassId,
    change: enum { created, deleted, newDesc, newPass, newPassAndDesc, unchanged },
};

pub const TexGroupChange = struct {
    rootTex: TexPassId,
    change: enum { created, deleted, newDesc, newPass, newPassAndDesc, unchanged },
};

pub const PhysicalBufLifetime = struct {
    bufDescId: BufPassId,
    earliest: u16,
    latest: u16,
};

pub const PhysicalTexLifetime = struct {
    texDescId: TexPassId,
    earliest: u16,
    latest: u16,
};

pub const BufferClear = struct {
    sharedBufIndex: u16,
    passAfterClear: PassId, // First Pass that happens Afterwards
};

pub const TextureClear = struct {
    sharedTexIndex: u16,
    passAfterClear: PassId, // First Pass that happens Afterwards
};

pub const TransientBuffer = struct {
    unusedCounter: u8 = 0,
    hardwareBuf: BufId,
    bufDescId: BufPassId,
};

pub const TransientTexture = struct {
    unusedCounter: u8 = 0,
    hardwareTex: TexId,
    texDescId: TexPassId,
};

pub const PassAccessRange = struct {
    firstBuf: u16,
    lastBuf: u16,
    firstTex: u16,
    lastTex: u16,
};

pub const GraphMemoryNode = struct {
    level: u16,
    pass: PassId,
    memWeight: i64, // bornBytes - dyingBytes,
};
