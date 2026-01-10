const ResourceSlot = @import("PushConstants.zig").ResourceSlot;
const TextureBase = @import("TextureBase.zig").TextureBase;
const vk = @import("../../modules/vk.zig").c;
const vh = @import("../systems/Helpers.zig");

pub const Texture = struct {
    allocation: vk.VmaAllocation,
    bindlessIndex: u32 = 0,
    base: TextureBase,

    pub const TexId = packed struct { val: u32 };
    pub const TexInf = struct { id: TexId, mem: vh.MemUsage, typ: vh.TextureType, width: u32, height: u32, depth: u32 = 1 };

    pub fn create(texInf: TexInf) TexInf {
        return texInf;
    }

    pub fn getResourceSlot(self: *const Texture) ResourceSlot {
        return ResourceSlot{ .index = self.bindlessIndex, .count = 1 };
    }
};
