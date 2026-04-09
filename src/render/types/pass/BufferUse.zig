const BufferMeta = @import("../res/BufferMeta.zig").BufferMeta;
const Buffer = @import("../res/Buffer.zig").Buffer;
const vhE = @import("../../help/Enums.zig");
const BufId = BufferMeta.BufId;

pub const BufferUse = struct {
    bufId: BufferMeta.BufId,
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    shaderSlot: ?u32 = null,

    pub fn init(bufId: BufferMeta.BufId, stage: vhE.PipeStage, access: vhE.PipeAccess, shaderSlot: ?u8) BufferUse {
        return .{ .bufId = bufId, .stage = stage, .access = access, .shaderSlot = if (shaderSlot) |slot| slot else null };
    }

    pub fn getNeededState(self: *const BufferUse) Buffer.BufferState {
        return .{ .stage = self.stage, .access = self.access };
    }
};
