const BufferBase = @import("BufferBase.zig").BufferBase;
const rc = @import("../../../configs/renderConfig.zig");
const PushData = @import("PushData.zig").PushData;
const vk = @import("../../../modules/vk.zig").c;
const vhE = @import("../../help/Enums.zig");

pub const Buffer = struct {
    base: [rc.MAX_IN_FLIGHT]BufferBase,
    descIndices: [rc.MAX_IN_FLIGHT]u32 = .{0} ** rc.MAX_IN_FLIGHT,

    lastUpdateFlightId: u8 = 0,
    maxCount: u32,
    curCount: u32,
    typ: vhE.BufferType = .Storage,
    update: vhE.UpdateType = .Overwrite,

    pub const BufId = packed struct { val: u32 };
    pub const BufInf = struct { id: BufId, mem: vhE.MemUsage, elementSize: u32, len: u32, typ: vhE.BufferType, update: vhE.UpdateType };

    pub fn create(bufInf: BufInf) BufInf {
        return bufInf;
    }
};
