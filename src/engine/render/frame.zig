const c = @import("../../c.zig");
const createSemaphore = @import("../sync/primitives.zig").createSemaphore;

pub const Frame = struct {
    cmdBuff: c.VkCommandBuffer = undefined,
    acqSem: c.VkSemaphore,
    index: u32 = undefined,

    pub fn init(gpi: c.VkDevice) !Frame {
        return Frame{
            .acqSem = try createSemaphore(gpi),
        };
    }

    pub fn deinit(self: *Frame, gpi: c.VkDevice) void {
        c.vkDestroySemaphore(gpi, self.acqSem, null);
    }
};
