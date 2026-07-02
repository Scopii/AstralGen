const TexDesc = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const ViewportId = @import("../.configs/idConfig.zig").ViewportId;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const WindowId = @import("../.configs/idConfig.zig").WindowId;
const PassId = @import("../.configs/idConfig.zig").PassId;
const TexId = @import("../.configs/idConfig.zig").TexId;
const BufId = @import("../.configs/idConfig.zig").BufId;

pub const TextureLink = struct {
    in: TexPassId,
    out: ?TexPassId = null,
};

pub const BufferLink = struct {
    in: BufPassId,
    out: ?BufPassId = null,
};

pub const TextureStringLink = struct {
    in: []const u8, // Should be String?
    out: ?[]const u8 = null, // Should be String?
};

pub const BufferStringLink = struct {
    in: []const u8, // Should be String?
    out: ?[]const u8 = null, // Should be String?
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
    bufDesc: BufDesc,
};

pub const TransientTexture = struct {
    unusedCounter: u8 = 0,
    hardwareTex: TexId,
    texDesc: TexDesc,
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

pub const PendingTexDeletion = struct {
    id: TexId,
    unusedCounter: u8 = 0,
};

pub const PendingBufDeletion = struct {
    id: BufId,
    unusedCounter: u8 = 0,
};
