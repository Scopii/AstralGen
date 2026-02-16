
const rc = @import("../../../configs/renderConfig.zig");
const PushData = @import("PushData.zig").PushData;
const vk = @import("../../../modules/vk.zig").c;
const Buffer = @import("Buffer.zig").Buffer;
const vhE = @import("../../help/Enums.zig");

pub const BufferMeta = struct {
    updateId: u8 = 0,
    elementSize: u32,
    typ: vhE.BufferType,
    update: vhE.UpdateType,

    pub const BufId = packed struct { val: u32 };

    pub const BufInf = struct {
        id: BufId,
        mem: vhE.MemUsage,
        elementSize: u32,
        len: u32,
        typ: vhE.BufferType,
        update: vhE.UpdateType,
    };

    pub fn create(bufInf: BufInf) BufInf {
        return bufInf;
    }
};
