const TexDesc = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const TexInf = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexInf;
const TexId = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexId;
const BufDesc = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const BufInf = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufInf;
const BufId = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufId;
pub const pe = @import("enums.zig");

pub const TextureLink = struct {
    in: pe.TextureEnum,
    out: ?pe.TextureEnum = null,
};

pub const BufferLink = struct {
    in: pe.BufferEnum,
    out: ?pe.BufferEnum = null,
};

pub const TextureAccess = struct {
    passEnum: pe.PassEnum,
    texInput: pe.TextureEnum,
    texOutput: ?pe.TextureEnum,
    access: enum { write, read },
};

pub const BufferAccess = struct {
    passEnum: pe.PassEnum,
    bufInput: pe.BufferEnum,
    bufOutput: ?pe.BufferEnum,
    access: enum { write, read },
};

pub const TextureDependancy = struct {
    texEnum: pe.TextureEnum,
    predecessor: pe.PassEnum,
    successor: pe.PassEnum,
};

pub const BufferDependancy = struct {
    bufEnum: pe.BufferEnum,
    predecessor: pe.PassEnum,
    successor: pe.PassEnum,
};

pub const GraphNode = struct {
    level: u16,
    passEnum: pe.PassEnum,
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
    rootPass: pe.PassEnum,
    rootBuf: pe.BufferEnum,
    bufDesc: BufDesc,
    startMapIndex: u16,
    endMapIndex: u16,
};

pub const TextureGroup = struct {
    rootPass: pe.PassEnum,
    rootTex: pe.TextureEnum,
    texDesc: TexDesc,
    startMapIndex: u16,
    endMapIndex: u16,
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
    bufDesc: BufDesc,
    earliest: u16,
    latest: u16,
};

pub const PhysicalTexLifetime = struct {
    texDesc: TexDesc,
    earliest: u16,
    latest: u16,
};

pub const BufferClear = struct {
    sharedBufIndex: u16,
    passAfterClear: pe.PassEnum, // First Pass that happens Afterwards
};

pub const TextureClear = struct {
    sharedTexIndex: u16,
    passAfterClear: pe.PassEnum, // First Pass that happens Afterwards
};

pub const TransientBuffer = struct {
    unusedCounter: u8 = 0,
    bufId: BufId,
    bufDesc: BufDesc,
};

pub const TransientTexture = struct {
    unusedCounter: u8 = 0,
    texId: TexId,
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
    passEnum: pe.PassEnum,
    memWeight: i64, // bornBytes - dyingBytes,
};
