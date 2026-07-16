const BufId = @import("../../../.configs/idConfig.zig").BufId;
const Buffer = @import("../res/Buffer.zig").Buffer;
const vhE = @import("../../help/Enums.zig");

pub const BufferFill = struct {
    bufId: BufId,
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    shaderSlot: ?u32 = null,

    pub const BufUseKind = enum { UniformRead, StorageRead, StorageWrite, StorageReadWrite, IndirectRead };
};
