const BufferStringLink = @import("../../../frameBuild/components.zig").BufferStringLink;
const Buffer = @import("../res/Buffer.zig").Buffer;
const vhE = @import("../../help/Enums.zig");

const BufId = @import("../res/BufferMeta.zig").BufferMeta.BufId;

pub const BufferFill = struct {
    bufId: BufId,
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    shaderSlot: ?u32 = null,

    pub const BufUseKind = enum { UniformRead, StorageRead, StorageWrite, StorageReadWrite, IndirectRead };

    pub fn init(bufId: BufId, stage: vhE.PipeStage, bufUseKind: BufUseKind, shaderSlot: ?u8) BufferFill {
        const access: vhE.PipeAccess = switch (bufUseKind) {
            .UniformRead => .UniformRead,
            .StorageRead => .StorageRead,
            .StorageWrite => .StorageWrite,
            .StorageReadWrite => .storageReadWrite,
            .IndirectRead => .IndirectRead,
        };

        return .{
            .bufId = bufId,
            .stage = stage,
            .access = access,
            .shaderSlot = if (shaderSlot) |slot| slot else null,
        };
    }

    pub fn getNeededState(self: *const BufferFill) Buffer.BufferState {
        return .{ .stage = self.stage, .access = self.access };
    }
};
