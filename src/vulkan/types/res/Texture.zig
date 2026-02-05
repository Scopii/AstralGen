const TextureBase = @import("TextureBase.zig").TextureBase;
const rc = @import("../../../configs/renderConfig.zig");
const PushData = @import("PushData.zig").PushData;
const vk = @import("../../../modules/vk.zig").c;
const vhE = @import("../../help/Enums.zig");

pub const Texture = struct {
    allocation: [rc.MAX_IN_FLIGHT]vk.VmaAllocation,
    desIndices: [rc.MAX_IN_FLIGHT]u32 = .{0} ** rc.MAX_IN_FLIGHT,
    base: [rc.MAX_IN_FLIGHT]TextureBase,
    update: vhE.UpdateType = .Overwrite,

    pub const TexId = packed struct { val: u32 };
    pub const TexInf = struct { id: TexId, mem: vhE.MemUsage, typ: vhE.TextureType, width: u32, height: u32, depth: u32 = 1, update: vhE.UpdateType };

    pub fn create(texInf: TexInf) TexInf {
        return texInf;
    }
};
