const PushConstants = @import("PushConstants.zig").PushConstants;
const TextureBase = @import("TextureBase.zig").TextureBase;
const vk = @import("../../../modules/vk.zig").c;
const vhE = @import("../../help/Enums.zig");

pub const Texture = struct {
    allocation: vk.VmaAllocation,
    bindlessIndex: u32 = 0,
    base: TextureBase,

    pub const TexId = packed struct { val: u32 };
    pub const TexInf = struct { id: TexId, mem: vhE.MemUsage, typ: vhE.TextureType, width: u32, height: u32, depth: u32 = 1};

    pub fn create(texInf: TexInf) TexInf {
        return texInf;
    }

    pub fn getResourceSlot(self: *const Texture) PushConstants.ResourceSlot {
        return .{ .index = self.bindlessIndex, .count = 1 };
    }
};
