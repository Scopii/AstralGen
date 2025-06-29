// src/engine/render/FrameData.zig
const c = @import("../../c.zig");
const check = @import("../error.zig").check;
const createSemaphore = @import("../sync/primitives.zig").createSemaphore;
const MAX_IN_FLIGHT = @import("../Renderer.zig").MAX_IN_FLIGHT;

/// Manages synchronization primitives for a single frame in flight.
pub const FrameData = struct {
    imageReady: c.VkSemaphore,
    renderDone: c.VkSemaphore,

    pub fn init(gpi: c.VkDevice) !FrameData {
        return .{
            .imageReady = try createSemaphore(gpi),
            .renderDone = try createSemaphore(gpi),
        };
    }

    pub fn deinit(self: *const FrameData, gpi: c.VkDevice) void {
        c.vkDestroySemaphore(gpi, self.imageReady, null);
        c.vkDestroySemaphore(gpi, self.renderDone, null);
    }
};
