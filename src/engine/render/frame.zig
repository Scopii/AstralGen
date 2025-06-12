const c = @import("../../c.zig");
const createCmdBuffer = @import("../render/cmd.zig").createCmdBuffer;
const createSemaphore = @import("../sync/primitives.zig").createSemaphore;

pub const Frame = struct {
    cmdBuff: c.VkCommandBuffer,
    acqSem: c.VkSemaphore,
    index: u32 = undefined,

    pub fn init(gpi: c.VkDevice, cmdPool: c.VkCommandPool) !Frame {
        return Frame{
            .cmdBuff = try createCmdBuffer(gpi, cmdPool),
            .acqSem = try createSemaphore(gpi),
        };
    }

    pub fn deinit(self: *Frame, gpi: c.VkDevice) void {
        c.vkDestroySemaphore(gpi, self.acqSem, null);
    }
};
