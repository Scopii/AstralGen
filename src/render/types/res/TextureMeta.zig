const rc = @import("../../../.configs/renderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const vhE = @import("../../help/Enums.zig");

pub const TextureMeta = struct {
    texType: vhE.TextureType,
    update: vhE.UpdateType,
    resize: vhE.ResizeType,
    mem: vhE.MemUsage,
    updateSlot: u8 = rc.MAX_IN_FLIGHT - 1,
    viewType: vk.VkImageViewType,
    format: vk.VkFormat,

    pub const TexId = packed struct { val: u32 };

    pub const TexInf = struct {
        id: TexId,
        mem: vhE.MemUsage,
        typ: vhE.TextureType,
        width: u32,
        height: u32,
        depth: u32 = 1,
        update: vhE.UpdateType,
        resize: vhE.ResizeType = .Block,
    };

    pub fn create(texInf: TexInf) TexInf {
        return texInf;
    }
};
