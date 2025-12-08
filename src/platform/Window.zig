const std = @import("std");
const c = @import("../c.zig");
const Swapchain = @import("../vulkan/SwapchainManager.zig").Swapchain;

pub const Window = struct {
    pub const WindowStatus = enum {
        active,
        inactive,
        needCreation,
        needUpdate,
        needDelete,
        needInactive,
        needActive,
    };
    handle: *c.SDL_Window,
    status: WindowStatus = .needCreation,
    renderId: u8,
    extent: c.VkExtent2D,
    id: u32,

    pub fn init(id: u32, sdlWindow: *c.SDL_Window, renderId: u8, extent: c.VkExtent2D) !Window {
        return Window{ .handle = sdlWindow, .renderId = renderId, .extent = extent, .id = id };
    }
};
