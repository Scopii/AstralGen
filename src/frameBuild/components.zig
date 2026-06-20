const TexDesc = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const TexInf = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexInf;
const TexId = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexId;
const BufDesc = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const BufInf = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufInf;
const BufId = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufId;
pub const pe = @import("enums.zig");

pub const PassId = struct { val: u16 };

pub const TextureLink = struct {
    in: pe.TextureEnum,
    out: ?pe.TextureEnum = null,
};

pub const BufferLink = struct {
    in: pe.BufferEnum,
    out: ?pe.BufferEnum = null,
};

pub const TextureAccess = struct {
    pass: PassId,
    texInput: pe.TextureEnum,
    texOutput: ?pe.TextureEnum,
    access: enum { write, read },
};

pub const BufferAccess = struct {
    pass: PassId,
    bufInput: pe.BufferEnum,
    bufOutput: ?pe.BufferEnum,
    access: enum { write, read },
};

pub const TextureDependancy = struct {
    texEnum: pe.TextureEnum,
    predecessor: PassId,
    successor: PassId,
};

pub const BufferDependancy = struct {
    bufEnum: pe.BufferEnum,
    predecessor: PassId,
    successor: PassId,
};

pub const GraphNode = struct {
    level: u16,
    pass: PassId,
};

pub const TextureLifetime = struct {
    texEnum: pe.TextureEnum,
    earliest: u16,
    latest: u16,
};

pub const BufferLifetime = struct {
    bufEnum: pe.BufferEnum,
    earliest: u16,
    latest: u16,
};

pub const BufGroupLifetime = struct {
    rootBuf: pe.BufferEnum,
    earliest: u16,
    latest: u16,
};

pub const TexGroupLifetime = struct {
    rootTex: pe.TextureEnum,
    earliest: u16,
    latest: u16,
};

pub const BufLevelLifetime = struct {
    bufEnum: pe.BufferEnum,
    firstLevel: u16,
    lastLevel: u16,
};

pub const TexLevelLifetime = struct {
    texEnum: pe.TextureEnum,
    firstLevel: u16,
    lastLevel: u16,
};

pub const BufferGroup = struct {
    rootPass: PassId,
    rootBuf: pe.BufferEnum,
    startMapIndex: u16,
    endMapIndex: u16,
    bufDesc: BufDesc,
};

pub const TextureGroup = struct {
    rootPass: PassId,
    rootTex: pe.TextureEnum,
    startMapIndex: u16,
    endMapIndex: u16,
    texDesc: TexDesc,
};

pub const BufGroupChange = struct {
    rootBuf: pe.BufferEnum,
    change: enum { created, deleted, newDesc, newPass, newPassAndDesc, unchanged },
};

pub const TexGroupChange = struct {
    rootTex: pe.TextureEnum,
    change: enum { created, deleted, newDesc, newPass, newPassAndDesc, unchanged },
};

pub const PhysicalBufLifetime = struct {
    bufDescEnum: pe.BufferEnum,
    earliest: u16,
    latest: u16,
};

pub const PhysicalTexLifetime = struct {
    texDescEnum: pe.TextureEnum,
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
    bufId: BufId,
    bufDescEnum: pe.BufferEnum,
};

pub const TransientTexture = struct {
    unusedCounter: u8 = 0,
    texId: TexId,
    texDescEnum: pe.TextureEnum,
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
