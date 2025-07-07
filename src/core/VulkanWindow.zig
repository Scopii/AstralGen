const std = @import("std");
const c = @import("../c.zig");
const PipelineType = @import("../engine/render/PipelineBucket.zig").PipelineType;
const Swapchain = @import("../engine/render/SwapchainManager.zig").Swapchain;

pub const windowStatus = enum {
    empty,
    active,
    inactive,
};

pub const VulkanWindow = struct {
    handle: *c.SDL_Window,
    extent: c.VkExtent2D,
    pipeType: PipelineType,
    status: windowStatus,
    id: u32,
    swapchain: ?Swapchain = null,

    pub fn init(width: c_int, height: c_int, id: u32, sdlWindow: *c.SDL_Window, pipeType: PipelineType) !VulkanWindow {
        return VulkanWindow{
            .handle = sdlWindow,
            .extent = c.VkExtent2D{ .width = @intCast(width), .height = @intCast(height) },
            .pipeType = pipeType,
            .id = id,
            .status = .empty,
        };
    }

    pub fn deinit(self: *VulkanWindow) void {
        c.SDL_DestroyWindow(self.handle);
    }
};
