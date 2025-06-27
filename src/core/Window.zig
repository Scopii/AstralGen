const std = @import("std");
const c = @import("../c.zig");

pub const Window = struct {
    handle: *c.SDL_Window,
    extent: c.VkExtent2D,
    close: bool = false,
    id: u32,

    pub fn manage(self: *Window) void {
        _ = c.SDL_GetWindowSize(self.handle, @ptrCast(&self.extent.width), @ptrCast(&self.extent.height));
        std.debug.print("SDL Dimensions: {} {}\n", .{ self.extent.width, self.extent.height });
        // Handle window minimization
        if (self.extent.width == 0 or self.extent.height == 0) {
            var event: c.SDL_Event = undefined;
            _ = c.SDL_WaitEvent(&event);
            std.debug.print("Minimized", .{});
        }
    }

    pub fn resize(self: *Window, width: c_int, height: c_int) void {
        _ = c.SDL_SetWindowSize(self.handle, width, height);
    }

    pub fn deinit(self: *Window) void {
        c.SDL_DestroyWindow(self.handle);
    }
};
