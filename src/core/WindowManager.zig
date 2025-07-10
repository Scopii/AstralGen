const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const Window = @import("Window.zig").Window;
const PipelineType = @import("../engine/render/PipelineBucket.zig").PipelineType;
const Swapchain = @import("../engine/render/SwapchainManager.zig").Swapchain;
const Renderer = @import("../engine/Renderer.zig").Renderer;

pub const WindowManager = struct {
    alloc: Allocator,
    windows: std.AutoHashMap(u32, Window),
    swapchainsToDraw: std.ArrayList(*Swapchain),
    openWindows: u32 = 0,
    close: bool = false,

    pub fn init(alloc: Allocator) !WindowManager {
        // Initialize SDL3 with video subsystem
        if (c.SDL_Init(c.SDL_INIT_VIDEO) != true) {
            std.log.err("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
            return error.SdlInitFailed;
        }

        return .{
            .alloc = alloc,
            .windows = std.AutoHashMap(u32, Window).init(alloc),
            .swapchainsToDraw = std.ArrayList(*Swapchain).init(alloc),
        };
    }

    pub fn deinit(self: *WindowManager) void {
        var iter = self.windows.valueIterator();
        while (iter.next()) |window| c.SDL_DestroyWindow(window.handle);
        self.windows.deinit();
        self.swapchainsToDraw.deinit();
        c.SDL_Quit();
    }

    pub fn addWindow(self: *WindowManager, title: [*c]const u8, renderer: *Renderer, width: c_int, height: c_int, pipeType: PipelineType) !void {
        const sdlHandle = c.SDL_CreateWindow(title, width, height, c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE) orelse {
            std.log.err("SDL_CreateWindow failed: {s}\n", .{c.SDL_GetError()});
            return error.WindowInitFailed;
        };
        const id = c.SDL_GetWindowID(sdlHandle);
        std.debug.print("Window ID {} created\n", .{id});
        _ = c.SDL_SetWindowFullscreen(sdlHandle, false);
        //_ = c.SDL_SetWindowRelativeMouseMode(window, true);
        //_ = c.SDL_SetWindowOpacity(sdlWindow, 0.5);
        var window = try Window.init(id, sdlHandle);
        const wantedExtent = c.VkExtent2D{ .width = @intCast(width), .height = @intCast(height) };
        try renderer.giveSwapchain(&window, pipeType, wantedExtent);
        try self.windows.put(id, window);
        self.openWindows += 1;
    }

    pub fn getWindowPtr(self: *WindowManager, id: u32) ?*Window {
        return self.windows.getPtr(id);
    }

    pub fn getSwapchainsToDraw(self: *WindowManager) ![]*Swapchain {
        self.swapchainsToDraw.clearRetainingCapacity();

        var iter = self.windows.valueIterator();
        while (iter.next()) |windowPtr| {
            if (windowPtr.status == .active) {
                try self.swapchainsToDraw.append(&windowPtr.swapchain.?);
            }
        }
        return self.swapchainsToDraw.items;
    }

    pub fn destroyWindow(self: *WindowManager, id: u32) void {
        if (self.windows.remove(id)) |removedWindow| c.SDL_DestroyWindow(removedWindow.handle);
        self.openWindows -= 1;
    }

    pub fn pollEvents(self: *WindowManager, renderer: *Renderer) !void {
        var event: c.SDL_Event = undefined;

        if (self.openWindows == 0) {
            if (c.SDL_WaitEvent(&event)) try self.processEvent(&event, renderer); // On pause wait for an event and process
            while (c.SDL_PollEvent(&event)) try self.processEvent(&event, renderer); // drain remaining events
        } else {
            while (c.SDL_PollEvent(&event)) try self.processEvent(&event, renderer); // When active process all events in queue
        }
    }

    fn processEvent(self: *WindowManager, event: *c.SDL_Event, renderer: *Renderer) !void {
        switch (event.type) {
            c.SDL_EVENT_QUIT => self.close = true,

            c.SDL_EVENT_WINDOW_CLOSE_REQUESTED,
            c.SDL_EVENT_WINDOW_MINIMIZED,
            c.SDL_EVENT_WINDOW_RESTORED,
            c.SDL_EVENT_WINDOW_RESIZED,
            => {
                const id = event.window.windowID;
                if (self.windows.getPtr(id)) |window| {
                    switch (event.type) {
                        c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                            try renderer.destroyWindow(window);
                            window.deinit();
                            _ = self.windows.remove(id);
                            std.debug.print("Window {} CLOSED.\n", .{id});
                        },
                        c.SDL_EVENT_WINDOW_MINIMIZED => {
                            window.status = .inactive;
                            self.openWindows -= 1;
                            std.debug.print("Window {} MINIMIZED.\n", .{id});
                        },
                        c.SDL_EVENT_WINDOW_RESTORED => {
                            window.status = .active;
                            self.openWindows += 1;
                            std.debug.print("Window {} RESTORED.\n", .{id});
                        },
                        c.SDL_EVENT_WINDOW_RESIZED => {
                            var newExtent: c.VkExtent2D = undefined;
                            _ = c.SDL_GetWindowSize(window.handle, @ptrCast(&newExtent.width), @ptrCast(&newExtent.height));
                            try renderer.renewSwapchain(window, newExtent);
                            _ = c.SDL_SetWindowSize(window.handle, @intCast(window.swapchain.?.extent.width), @intCast(window.swapchain.?.extent.height));
                            std.debug.print("Window {} RESIZED.\n", .{id});
                        },
                        else => {},
                    }
                }
            },

            else => {},
        }
    }
};
