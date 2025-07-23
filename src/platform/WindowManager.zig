const std = @import("std");
const c = @import("../c.zig");
const MemoryManger = @import("../core/MemoryManager.zig").MemoryManager;
const Window = @import("Window.zig").Window;
const PipelineType = @import("../vulkan/PipelineBucket.zig").PipelineType;
const Swapchain = @import("../vulkan/SwapchainManager.zig").Swapchain;
const Renderer = @import("../vulkan/Renderer.zig").Renderer;

pub const WindowManager = struct {
    memoryMan: *MemoryManger,
    windows: std.AutoHashMap(u32, Window),
    swapchainsToDraw: std.ArrayList(u32),
    swapchainsToDelete: std.ArrayList(u32),
    emptyWindows: std.ArrayList(Window),
    openWindows: u32 = 0,
    needSwapchainUpdate: bool = true,
    needRenderResize: bool = true,
    close: bool = false,

    pub fn init(memoryMan: *MemoryManger) !WindowManager {
        if (c.SDL_Init(c.SDL_INIT_VIDEO) != true) {
            std.log.err("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
            return error.SdlInitFailed;
        }
        const alloc = memoryMan.getAllocator();

        return .{
            .memoryMan = memoryMan,
            .windows = std.AutoHashMap(u32, Window).init(alloc),
            .swapchainsToDraw = std.ArrayList(u32).init(alloc),
            .swapchainsToDelete = std.ArrayList(u32).init(alloc),
            .emptyWindows = std.ArrayList(Window).init(alloc),
        };
    }

    pub fn deinit(self: *WindowManager) void {
        var iter = self.windows.valueIterator();
        while (iter.next()) |window| c.SDL_DestroyWindow(window.handle);
        self.windows.deinit();
        self.emptyWindows.deinit();
        self.swapchainsToDelete.deinit();
        self.swapchainsToDraw.deinit();
        c.SDL_Quit();
    }

    pub fn addWindow(self: *WindowManager, title: [*c]const u8, width: c_int, height: c_int, pipeType: PipelineType) !void {
        const sdlHandle = c.SDL_CreateWindow(title, width, height, c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE) orelse {
            std.log.err("SDL_CreateWindow failed: {s}\n", .{c.SDL_GetError()});
            return error.WindowInitFailed;
        };
        const id = c.SDL_GetWindowID(sdlHandle);
        _ = c.SDL_SetWindowFullscreen(sdlHandle, false);
        //_ = c.SDL_SetWindowRelativeMouseMode(window, true);
        //_ = c.SDL_SetWindowOpacity(sdlWindow, 0.5);

        const window = try Window.init(id, sdlHandle, pipeType, c.VkExtent2D{ .width = @intCast(width), .height = @intCast(height) });
        try self.emptyWindows.append(window);
        try self.windows.put(id, window);
        self.needSwapchainUpdate = true;
        self.openWindows += 1;
        std.debug.print("Window ID {} created\n", .{id});
    }

    pub fn getEmptyWindows(self: *WindowManager) ![]Window {
        return self.emptyWindows.items;
    }

    pub fn getDeletedWindows(self: *WindowManager) ![]u32 {
        return self.swapchainsToDelete.items;
    }

    pub fn getWindowPtr(self: *WindowManager, id: u32) ?*Window {
        return self.windows.getPtr(id);
    }

    pub fn getSwapchainsToDraw(self: *WindowManager) ![]u32 {
        self.swapchainsToDraw.clearRetainingCapacity();
        var iter = self.windows.valueIterator();

        while (iter.next()) |windowPtr| {
            if (windowPtr.status == .active) try self.swapchainsToDraw.append(windowPtr.id);
        }
        return self.swapchainsToDraw.items;
    }

    pub fn destroyWindow(self: *WindowManager, id: u32) void {
        if (self.windows.remove(id)) |removedWindow| c.SDL_DestroyWindow(removedWindow.handle);
    }

    pub fn pollEvents(self: *WindowManager) !void {
        var event: c.SDL_Event = undefined;

        if (self.openWindows == 0) {
            if (c.SDL_WaitEvent(&event)) try self.processEvent(&event); // On pause wait for an event and process
            while (c.SDL_PollEvent(&event)) try self.processEvent(&event); // drain remaining events
        } else {
            while (c.SDL_PollEvent(&event)) try self.processEvent(&event); // When active process all events in queue
        }
    }

    fn processEvent(self: *WindowManager, event: *c.SDL_Event) !void {
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
                            try self.swapchainsToDelete.append(window.id);
                            if (window.status == .active) self.openWindows -= 1;
                            window.deinit();
                            _ = self.windows.remove(id);
                            self.needSwapchainUpdate = true;
                            std.debug.print("Window {} CLOSED.\n", .{id});
                        },
                        c.SDL_EVENT_WINDOW_MINIMIZED => {
                            window.status = .inactive;
                            self.openWindows -= 1;
                            self.needSwapchainUpdate = true;
                            std.debug.print("Window {} MINIMIZED.\n", .{id});
                        },
                        c.SDL_EVENT_WINDOW_RESTORED => {
                            window.status = .active;
                            self.openWindows += 1;
                            self.needSwapchainUpdate = true;
                            std.debug.print("Window {} RESTORED.\n", .{id});
                        },
                        c.SDL_EVENT_WINDOW_RESIZED => {
                            var newExtent: c.VkExtent2D = undefined;
                            _ = c.SDL_GetWindowSize(window.handle, @ptrCast(&newExtent.width), @ptrCast(&newExtent.height));
                            window.extent = newExtent;
                            try self.emptyWindows.append(window.*);
                            self.needRenderResize = true;
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
