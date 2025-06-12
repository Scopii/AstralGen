const std = @import("std");
const c = @import("../../c.zig");
const Allocator = std.mem.Allocator;

pub fn createSurface(window: *c.SDL_Window, instance: c.VkInstance) !c.VkSurfaceKHR {
    var surface: c.VkSurfaceKHR = undefined;
    if (c.SDL_Vulkan_CreateSurface(window, @ptrCast(instance), null, @ptrCast(&surface)) == false) {
        std.log.err("Unable to create Vulkan surface: {s}\n", .{c.SDL_GetError()});
        return error.VkSurface;
    }
    return surface;
}
