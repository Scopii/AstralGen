const BufferStringLink = @import("../../../renderGraph/components.zig").BufferStringLink;
const BufId = @import("../../../.configs/idConfig.zig").BufId;
const Buffer = @import("../res/Buffer.zig").Buffer;
const vhE = @import("../../help/Enums.zig");

pub const BufferFill = struct {
    bufId: BufId,
    stage: vhE.PipeStage,
    access: vhE.PipeAccess,
    shaderSlot: ?u32,

    pub const BufUseKind = enum { UniformRead, StorageRead, StorageWrite, StorageReadWrite, IndirectRead };
};

pub const BufferSlot = struct {
    bufLink: BufferStringLink,
    stage: vhE.PipeStage,
    access: vhE.PipeAccess,
    shaderSlot: ?u32,

    pub const BufUseKind = enum { UniformRead, StorageRead, StorageWrite, StorageReadWrite, IndirectRead };

    pub fn init(bufLink: BufferStringLink, stage: vhE.PipeStage, bufUseKind: BufUseKind, shaderSlot: ?u8) BufferSlot {
        const access: vhE.PipeAccess = switch (bufUseKind) {
            .UniformRead => .UniformRead,
            .StorageRead => .StorageRead,
            .StorageWrite => .StorageWrite,
            .StorageReadWrite => .storageReadWrite,
            .IndirectRead => .IndirectRead,
        };

        return .{
            .bufLink = bufLink,
            .stage = stage,
            .access = access,
            .shaderSlot = if (shaderSlot) |slot| slot else null,
        };
    }
};
