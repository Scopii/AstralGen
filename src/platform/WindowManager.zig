const std = @import("std");
const c = @import("../c.zig");
const MemoryManger = @import("../core/MemoryManager.zig").MemoryManager;
const Window = @import("Window.zig").Window;
const PipelineType = @import("../vulkan/PipelineBucket.zig").PipelineType;
const Swapchain = @import("../vulkan/SwapchainManager.zig").Swapchain;
const Renderer = @import("../vulkan/Renderer.zig").Renderer;
const CreateMapArray = @import("../structures/MapArray.zig").CreateMapArray;

pub const WindowManager = struct {
    memoryMan: *MemoryManger,
    windows: CreateMapArray(Window, 24, u8, 24, 0),
    swapchainsToChange: std.ArrayList(Window),
    swapchainsToDraw: std.ArrayList(u32),
    openWindows: u32 = 0,
    close: bool = false,

    pub fn init(memoryMan: *MemoryManger) !WindowManager {
        if (c.SDL_Init(c.SDL_INIT_VIDEO) != true) {
            std.log.err("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
            return error.SdlInitFailed;
        }
        const alloc = memoryMan.getAllocator();

        return .{
            .memoryMan = memoryMan,
            .windows = .{},
            .swapchainsToChange = std.ArrayList(Window).init(alloc),
            .swapchainsToDraw = std.ArrayList(u32).init(alloc),
        };
    }

    pub fn deinit(self: *WindowManager) void {
        for (0..self.windows.getCount()) |_| {
            const windowPtr = self.windows.getLastPtr();
            c.SDL_DestroyWindow(windowPtr.handle);
            self.windows.removeLast();
        }
        self.swapchainsToChange.deinit();
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

        var window = try Window.init(id, sdlHandle, pipeType, c.VkExtent2D{ .width = @intCast(width), .height = @intCast(height) });
        try self.swapchainsToChange.append(window);
        window.status = .active;
        self.windows.set(@intCast(id), window);
        self.openWindows += 1;
        std.debug.print("Window ID {} created\n", .{id});
    }

    pub fn getWindowPtr(self: *WindowManager, id: u32) *Window {
        return try self.windows.getPtrFromKey(id);
    }

    pub fn getSwapchainsToDraw2(self: *WindowManager) ![]u32 {
        self.swapchainsToDraw.clearRetainingCapacity();
        const count = self.windows.getCount();
        if (count == 0) return self.swapchainsToDraw.items;

        for (0..count) |i| {
            const windowPtr = self.windows.getPtrAtIndex(@intCast(i));
            if (windowPtr.status == .active) try self.swapchainsToDraw.append(windowPtr.id);
        }
        return self.swapchainsToDraw.items;
    }

    pub fn cleanupWindows(self: *WindowManager) !void {
        for (self.swapchainsToChange.items) |window| {
            if (window.status == .needDelete) try self.destroyWindow(window.id);
        }
        self.swapchainsToChange.clearRetainingCapacity();
    }

    pub fn destroyWindow(self: *WindowManager, id: u32) !void {
        const window = self.windows.get(@intCast(id));
        c.SDL_DestroyWindow(window.handle);
        self.windows.removeAtKey(@intCast(id));
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
                const window = self.windows.getPtr(@intCast(id));

                switch (event.type) {
                    c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                        if (window.status == .active) self.openWindows -= 1;
                        window.status = .needDelete;
                        try self.swapchainsToChange.append(window.*);
                        std.debug.print("Window {} CLOSED.\n", .{id});
                    },
                    c.SDL_EVENT_WINDOW_MINIMIZED => {
                        window.status = .inactive;
                        try self.swapchainsToChange.append(window.*);
                        self.openWindows -= 1;
                        std.debug.print("Window {} MINIMIZED.\n", .{id});
                    },
                    c.SDL_EVENT_WINDOW_RESTORED => {
                        window.status = .active;
                        try self.swapchainsToChange.append(window.*);
                        self.openWindows += 1;
                        std.debug.print("Window {} RESTORED.\n", .{id});
                    },
                    c.SDL_EVENT_WINDOW_RESIZED => {
                        window.status = .needUpdate;
                        try self.swapchainsToChange.append(window.*);
                        window.status = .active;
                        var newExtent: c.VkExtent2D = undefined;
                        _ = c.SDL_GetWindowSize(window.handle, @ptrCast(&newExtent.width), @ptrCast(&newExtent.height));
                        window.extent = newExtent;
                        std.debug.print("Window {} RESIZED.\n", .{id});
                    },
                    else => {},
                }
            },
            else => {},
        }
    }
};
