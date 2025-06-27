const std = @import("std");
const c = @import("../c.zig");

pub const VulkanWindow = struct {
    handle: *c.SDL_Window,
    extent: c.VkExtent2D,
    id: u32,

    pub fn init(width: c_int, height: c_int, id: u32, sdlWindow: *c.SDL_Window) !VulkanWindow {
        return VulkanWindow{
            .handle = sdlWindow,
            .extent = c.VkExtent2D{ .width = @intCast(width), .height = @intCast(height) },
            .id = id,
        };
    }

    pub fn resize(self: *VulkanWindow, width: u32, height: u32) void {
        _ = c.SDL_SetWindowSize(self.handle, width, height);
    }

    pub fn deinit(self: *VulkanWindow) void {
        c.SDL_DestroyWindow(self.handle);
    }
};
