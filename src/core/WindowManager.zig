const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const VulkanWindow = @import("VulkanWindow.zig").VulkanWindow;
const PipelineType = @import("../engine/render/PipelineBucket.zig").PipelineType;
const Renderer = @import("../engine/Renderer.zig").Renderer;

pub const WindowManager = struct {
    alloc: Allocator,
    windows: std.AutoHashMap(u32, VulkanWindow),
    paused: bool = false,
    close: bool = false,

    pub fn init(alloc: Allocator) !WindowManager {
        // Initialize SDL3 with video subsystem
        if (c.SDL_Init(c.SDL_INIT_VIDEO) != true) {
            std.log.err("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
            return error.SdlInitFailed;
        }
        return .{
            .alloc = alloc,
            .windows = std.AutoHashMap(u32, VulkanWindow).init(alloc),
        };
    }

    pub fn deinit(self: *WindowManager) void {
        var iter = self.windows.valueIterator();
        while (iter.next()) |window| {
            c.SDL_DestroyWindow(window.handle);
        }
        self.windows.deinit();
        c.SDL_Quit();
    }

    pub fn createWindow(self: *WindowManager, title: [*c]const u8, width: c_int, height: c_int, pipeType: PipelineType) !void {
        const sdlWindow = c.SDL_CreateWindow(title, width, height, c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE) orelse {
            std.log.err("SDL_CreateWindow failed: {s}\n", .{c.SDL_GetError()});
            return error.WindowInitFailed;
        };
        const id = c.SDL_GetWindowID(sdlWindow);
        std.debug.print("vkWindow created (ID {})\n", .{id});
        //_ = c.SDL_SetWindowRelativeMouseMode(window, true);
        _ = c.SDL_SetWindowFullscreen(sdlWindow, false);

        const vkWindow = try VulkanWindow.init(width, height, id, sdlWindow, pipeType);

        try self.windows.put(id, vkWindow);
    }

    pub fn pollEvents(self: *WindowManager, renderer: *Renderer) !void {
        var event: c.SDL_Event = undefined;

        if (self.paused) {
            // When paused, wait for an event and process it
            if (c.SDL_WaitEvent(&event)) {
                try self.processEvent(&event, renderer);
            }
            // drain remaining events
            while (c.SDL_PollEvent(&event)) {
                try self.processEvent(&event, renderer);
            }
        } else {
            // When active process all events in the queue
            while (c.SDL_PollEvent(&event)) {
                try self.processEvent(&event, renderer);
            }
        }
    }

    fn processEvent(self: *WindowManager, event: *c.SDL_Event, renderer: *Renderer) !void {
        switch (event.type) {
            c.SDL_EVENT_QUIT => self.close = true,
            c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                const id = event.window.windowID;
                if (self.windows.getPtr(id)) |window| {
                    std.debug.print("Window {} CLOSE_REQUESTED.\n", .{window.id});
                    try renderer.destroyWindow(id);
                    window.deinit();
                    _ = self.windows.remove(id);
                }
            },
            c.SDL_EVENT_WINDOW_MINIMIZED => {
                const id = event.window.windowID;
                if (self.windows.getPtr(id)) |window| {
                    std.debug.print("Window {} MINIMIZED.\n", .{window.id});
                    self.paused = true;
                }
            },
            c.SDL_EVENT_WINDOW_RESTORED => {
                const id = event.window.windowID;
                if (self.windows.getPtr(id)) |window| {
                    std.debug.print("Window {} RESTORED.\n", .{window.id});
                    self.paused = false; // Resume normal operation
                }
            },
            c.SDL_EVENT_WINDOW_RESIZED => {
                const id = event.window.windowID;
                if (self.windows.getPtr(id)) |window| {
                    std.debug.print("Resize Called\n", .{});
                    var newExtent: c.VkExtent2D = undefined;
                    _ = c.SDL_GetWindowSize(window.handle, @ptrCast(&newExtent.width), @ptrCast(&newExtent.height));
                    window.extent = newExtent;
                    try renderer.renewSwapchain(window);
                }
            },
            else => {},
        }
    }

    pub fn getWindow(self: *WindowManager, id: u32) !VulkanWindow {
        return self.windows.get(id) orelse error.WindowNotFound;
    }

    pub fn destroyWindow(self: *WindowManager, id: u32) void {
        if (self.windows.remove(id)) |removed_window| {
            c.SDL_DestroyWindow(removed_window.handle);
        }
    }
};
