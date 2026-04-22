const rc = @import("../../../.configs/renderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const vhE = @import("../../help/Enums.zig");
const std = @import("std");

pub const BufferMeta = struct {
    typ: vhE.BufferType,
    update: vhE.UpdateType,
    resize: vhE.ResizeType,
    mem: vhE.MemUsage,
    updateSlot: u8 = rc.MAX_IN_FLIGHT - 1,
    lastUpdateFrame: u64 = std.math.maxInt(u64),
    elementSize: u32,

    pub const BufId = packed struct { val: u32 };

    pub const BufInf = struct {
        id: BufId,
        mem: vhE.MemUsage,
        elementSize: u32,
        len: u32,
        typ: vhE.BufferType,
        update: vhE.UpdateType,
        resize: vhE.ResizeType = .Block,
    };

    pub fn create(bufInf: BufInf) BufInf {
        return bufInf;
    }
};
