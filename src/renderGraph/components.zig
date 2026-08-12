const TexDesc = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const PassId = @import("../.configs/idConfig.zig").PassId;
const TexId = @import("../.configs/idConfig.zig").TexId;
const BufId = @import("../.configs/idConfig.zig").BufId;
const rc = @import("../.configs/renderConfig.zig");


pub const TextureStringLink = struct {
    in: []const u8, // Should be String?
    from: ?[]const u8 = null, // Should be String?
};

pub const BufferStringLink = struct {
    in: []const u8, // Should be String?
    from: ?[]const u8 = null, // Should be String?
};

pub const Dependancy = struct {
    predecessor: PassId,
    successor: PassId,
};

pub const GraphNode = struct {
    level: u16,
    passId: PassId,
};

pub const PassLifetime = struct {
    earliest: u16,
    latest: u16,
};

pub const GraphLifetime = struct {
    firstLevel: u16,
    lastLevel: u16,
};

pub const BufferClear = struct {
    sharedIndex: u16,
    rootResource: BufPassId,
    passAfterClear: PassId, // First Pass that happens Afterwards
};

pub const TextureClear = struct {
    sharedIndex: u16,
    rootResource: TexPassId,
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
    first: u16,
    last: u16,
};

pub const GraphMemoryNode = struct {
    level: u16,
    passId: PassId,
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

pub const TexInstance = struct {
    texPassId: TexPassId,
    passId: PassId,
    rootPassId: ?PassId,
    access: enum { write, read },
};

pub const BufInstance = struct {
    bufPassId: BufPassId,
    passId: PassId,
    rootPassId: ?PassId,
    access: enum { write, read },
};

pub const BufLifetime = struct {
    bufPassId: BufPassId,
    earliestPass: u16,
    latestPass: u16,
};

pub const TexLifetime = struct {
    texPassId: TexPassId,
    earliestPass: u16,
    latestPass: u16,
};

pub const PhysBufLifetime = struct {
    bufPassId: BufPassId,
    earliest: u16,
    latest: u16,
};

pub const PhysTexLifetime = struct {
    texPassId: TexPassId,
    earliest: u16,
    latest: u16,
};
