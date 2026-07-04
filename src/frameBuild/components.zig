const TexDesc = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const PassId = @import("../.configs/idConfig.zig").PassId;
const TexId = @import("../.configs/idConfig.zig").TexId;
const BufId = @import("../.configs/idConfig.zig").BufId;
const rc = @import("../.configs/renderConfig.zig");

pub const ResPassId = union(enum) { texPassId: TexPassId, bufPassId: BufPassId };

pub const TransientSlot = union(enum) { buf: TransientBuffer, tex: TransientTexture };

pub const ResLink = struct { in: u16, out: u16 };

pub fn getResKey(resId: anytype) u16 {
    return switch (@TypeOf(resId)) {
        BufPassId => resId.val(),
        TexPassId => resId.val() + rc.BUF_MAX,
        ResPassId => switch (resId) { // new: unwrap the union tag first
            .bufPassId => |id| id.val(),
            .texPassId => |id| id.val() + rc.BUF_MAX,
        },
        else => @compileError("Invalid Res Id"),
    };
}

pub fn getResTyp(resKey: u16) enum { Buf, Tex } {
    return if (resKey >= rc.BUF_MAX) .Tex else .Buf;
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
    rootResource: u16,
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
    rootResource: u16,
    change: ResUpdate,
};

pub const PhysicalResLifetime = struct {
    resKey: u16,
    earliest: u16,
    latest: u16,
};

pub const ResourceClear = struct {
    sharedIndex: u16,
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
