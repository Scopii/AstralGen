const TexDesc = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const ResPassId = @import("../.configs/idConfig.zig").ResPassId;
const PassId = @import("../.configs/idConfig.zig").PassId;
const TexId = @import("../.configs/idConfig.zig").TexId;
const BufId = @import("../.configs/idConfig.zig").BufId;
const rc = @import("../.configs/renderConfig.zig");

pub const ResLink = struct { in: ResPassId, out: ResPassId };

pub fn bufToRes(bufPassId: BufPassId) ResPassId {
    return .id(bufPassId.val());
}

pub fn texToRes(texPassId: TexPassId) ResPassId {
    return .id(texPassId.val() + rc.BUF_MAX);
}

pub fn resToBuf(resPassId: ResPassId) BufPassId {
    return .id(resPassId.val());
}
pub fn resToTex(resPassId: ResPassId) TexPassId {
    return .id(resPassId.val() - rc.BUF_MAX);
}

pub fn getResTyp(resPassId: ResPassId) enum { Tex, Buf } { // parameter type changed
    return if (resPassId.val() >= rc.BUF_MAX) .Tex else .Buf;
}

// pub const TextureLink = struct {
//     in: TexPassId,
//     out: ?TexPassId = null,
// };

// pub const BufferLink = struct {
//     in: BufPassId,
//     out: ?BufPassId = null,
// };

pub const TextureStringLink = struct {
    in: []const u8, // Should be String?
    out: ?[]const u8 = null, // Should be String?
};

pub const BufferStringLink = struct {
    in: []const u8, // Should be String?
    out: ?[]const u8 = null, // Should be String?
};

pub const Access = struct {
    pass: PassId,
    input: ResPassId,
    output: ?ResPassId,
    access: enum { write, read },
};

pub const Dependancy = struct {
    resource: ResPassId,
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

pub const GroupLifetime = struct {
    rootResource: ResPassId,
    earliestPass: u16,
    latestPass: u16,
};

pub const GraphLifetime = struct {
    firstLevel: u16,
    lastLevel: u16,
};

pub const ResDesc = union(enum) {
    texDesc: TexDesc,
    bufDesc: BufDesc,

    pub fn isTransient(self: *const ResDesc) bool {
        return switch (self.*) {
            .bufDesc => |desc| desc.share == .transient,
            .texDesc => |desc| desc.share == .transient,
        };
    }
};

pub const Group = struct {
    rootPass: PassId,
    firstMapIndex: u16,
    lastMapIndex: u16,
    desc: ResDesc,
};

pub const GroupChange = struct {
    pub const ResUpdate = enum {
        created,
        deleted,
        newDesc,
        newPass,
        newPassAndDesc,
        unchanged,
    };
    rootResource: ResPassId,
    change: ResUpdate,
};

pub const PhysicalResLifetime = struct {
    resKey: ResPassId,
    earliest: u16,
    latest: u16,
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
