const std = @import("std");
const c = @import("../c.zig");

pub const App = struct {
    window: *c.SDL_Window,
    extent: c.VkExtent2D,
    close: bool = false,

    pub fn init() !App {
        const extent = c.VkExtent2D{ .width = 1920, .height = 1080 };

        // Initialize SDL3 with video subsystem
        if (c.SDL_Init(c.SDL_INIT_VIDEO) != true) {
            std.log.err("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
            return error.SdlInitFailed;
        }

        const window = c.SDL_CreateWindow(
            "AstralGen",
            extent.width,
            extent.height,
            c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE,
        ) orelse {
            std.log.err("SDL_CreateWindow failed: {s}\n", .{c.SDL_GetError()});
            return error.WindowInitFailed;
        };

        //_ = c.SDL_SetWindowRelativeMouseMode(window, true);
        _ = c.SDL_SetWindowFullscreen(window, false);

        return App{ .window = window, .extent = extent };
    }

    pub fn pollEvents(self: *App) void {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != false) {
            switch (event.type) {
                c.SDL_EVENT_QUIT => self.close = true,
                else => {},
            }
        }
    }

    pub fn handle(self: *App) void {
        _ = c.SDL_GetWindowSize(self.window, @ptrCast(&self.extent.width), @ptrCast(&self.extent.height));
        // Handle window minimization
        if (self.extent.width == 0 or self.extent.height == 0) {}
    }

    pub fn deinit(self: *App) void {
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }
};
