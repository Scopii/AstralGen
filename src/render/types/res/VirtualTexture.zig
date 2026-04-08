const rc = @import("../../../.configs/renderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const vhE = @import("../../help/Enums.zig");

pub const VirtualAttachment = struct {
    name: []const u8,
    mem: vhE.MemUsage,
    texTyp: vhE.TextureType,
    width: u32,
    height: u32,
    depth: u32 = 1,
    update: vhE.UpdateType,
    resize: vhE.ResizeType = .Block,
    scaling: f32 = 1.0,

    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    layout: vhE.ImageLayout,
    clear: bool,
};
