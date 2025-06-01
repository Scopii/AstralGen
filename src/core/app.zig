const std = @import("std");
const c = @import("../c.zig");

pub const App = struct {
    window: *c.SDL_Window,
    extent: c.VkExtent2D,
    curr_width: c_int = undefined,
    curr_height: c_int = undefined,
    close: bool = false,

    pub fn init() !App {
        const extent = c.VkExtent2D{ .width = 1280, .height = 720 };

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
        _ = c.SDL_GetWindowSize(self.window, &self.curr_width, &self.curr_height);

        // Handle window minimization
        if (self.curr_width == 0 or self.curr_height == 0) {
            self.pollEvents();
        }
    }

    pub fn deinit(self: *App) void {
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }
};
