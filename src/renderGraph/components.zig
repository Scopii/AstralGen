const PassTextureUpdate = @import("../renderAssigner/RenderAssignerQueue.zig").RenderAssignerEvent.PassTextureUpdate;
const PassBufferUpdate = @import("../renderAssigner/RenderAssignerQueue.zig").RenderAssignerEvent.PassBufferUpdate;
const TexDesc = @import("../render/types/res/Texture.zig").TexDesc;
const BufDesc = @import("../render/types/res/Buffer.zig").BufDesc;
const RingList = @import("../.structures/RingList.zig").RingList;
const TexInf = @import("../render/types/res/Texture.zig").TexInf;
const BufInf = @import("../render/types/res/Buffer.zig").BufInf;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const PassId = @import("../.configs/idConfig.zig").PassId;
const TexId = @import("../.configs/idConfig.zig").TexId;
const BufId = @import("../.configs/idConfig.zig").BufId;
const rc = @import("../.configs/renderConfig.zig");
const vhE = @import("../render/help/Enums.zig");

pub const TextureStringLink = struct {
    in: []const u8, // Should be String?
    from: ?[]const u8 = null, // Should be String?
};

pub const TextureLink = struct {
    in: TexPassId,
    from: ?PassId,
};

pub const BufferStringLink = struct {
    in: []const u8, // Should be String?
    from: ?[]const u8 = null, // Should be String?
};

pub const BufferLink = struct {
    in: BufPassId,
    from: ?PassId,
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
    earliest: u16,
    latest: u16,
};

pub const ManualBuf = struct {
    updateTyp: vhE.UpdateType,
    subBufs: RingList(BufId, rc.MAX_IN_FLIGHT) = .{},
};

pub const SubResTexture = struct {
    lastUsedFrame: u64 = 0,
    texId: TexId,
    texInf: TexInf,
};

pub const ManualTex = struct {
    updateTyp: vhE.UpdateType,
    subTexes: RingList(TexId, rc.MAX_IN_FLIGHT) = .{},
};

pub const SubResBuffer = struct {
    lastUsedFrame: u64 = 0,
    bufId: BufId,
    bufInf: BufInf,
};

pub const TransientBuffer = struct {
    lastUsedFrame: u64,
    hardwareBuf: BufId,
    bufDesc: BufDesc,
};

pub const TransientTexture = struct {
    lastUsedFrame: u64,
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
    viaAttachment: bool, // Could be made Reference Enum
};

pub const BufReference = struct {
    bufPassId: BufPassId,
    passId: PassId,
    rootPassId: ?PassId,
    access: enum { write, read },
};

pub const BufLifetime = struct {
    bufPassId: BufPassId,
    earliest: u16,
    latest: u16,
};

pub const TexLifetime = struct {
    texPassId: TexPassId,
    earliest: u16,
    latest: u16,
    firstUseIsAttachment: bool,
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

pub const ResRequest = union(enum) {
    createBuf: BufId,
    createTex: TexId,
    destroyBuf: BufId,
    destroyTex: TexId,
    updateBuf: BufId,
    updateTex: TexId,
};
