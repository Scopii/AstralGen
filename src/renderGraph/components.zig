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

pub const PassLink = struct {
    predecessor: []const u8, // Should be String?
};

pub const Dependency = struct {
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
    bufPassId: BufPassId,
    passAfterClear: PassId, // First Pass that happens Afterwards
};

pub const TextureClear = struct {
    sharedIndex: u16,
    texPassId: TexPassId,
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

pub const PassRefRange = struct {
    first: u16,
    last: u16,
};

pub const GraphMemoryNode = struct {
    level: u16,
    passId: PassId,
    memWeight: i64, // bornBytes - dyingBytes,
};

pub const ResourceVersion = struct {
    latestWriter: ?PassId = null, // pass that wrote the newest version, null = start version
    latestIsRead: bool = false, // newest version already has readers
};

pub const TexReference = struct {
    texPassId: TexPassId,
    passId: PassId,
    rootPassId: ?PassId,
    access: enum { write, read },
};

pub const BufReference = struct {
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

pub const SharedBuffer = struct {
    earliest: u16,
    latest: u16,
    bufDesc: BufDesc,
};

pub const SharedTexture = struct {
    earliest: u16,
    latest: u16,
    texDesc: TexDesc,
};
