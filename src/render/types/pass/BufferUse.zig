const BufferLink = @import("../../../frameBuild/components.zig").BufferLink;
const Buffer = @import("../res/Buffer.zig").Buffer;
const vhE = @import("../../help/Enums.zig");

pub const BufferUse = struct {
    bufLink: BufferLink,
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    shaderSlot: ?u32 = null,

    pub fn init(bufLink: BufferLink, stage: vhE.PipeStage, access: vhE.PipeAccess, shaderSlot: ?u8) BufferUse {
        return .{ .bufLink = bufLink, .stage = stage, .access = access, .shaderSlot = if (shaderSlot) |slot| slot else null };
    }

    pub fn getNeededState(self: *const BufferUse) Buffer.BufferState {
        return .{ .stage = self.stage, .access = self.access };
    }
};
