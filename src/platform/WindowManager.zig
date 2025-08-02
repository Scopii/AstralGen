const std = @import("std");
const c = @import("../c.zig");
const MemoryManger = @import("../core/MemoryManager.zig").MemoryManager;
const Window = @import("Window.zig").Window;
const PipelineType = @import("../vulkan/PipelineBucket.zig").PipelineType;
const Swapchain = @import("../vulkan/SwapchainManager.zig").Swapchain;
const Renderer = @import("../vulkan/Renderer.zig").Renderer;
const CreateMapArray = @import("../structures/MapArray.zig").CreateMapArray;
const MAX_WINDOWS = @import("../config.zig").MAX_WINDOWS;

pub const WindowManager = struct {
    windows: CreateMapArray(Window, MAX_WINDOWS, u8, MAX_WINDOWS, 0) = .{},
    changedWindows: std.BoundedArray(*Window, MAX_WINDOWS) = .{},
    openWindows: u8 = 0,
    close: bool = false,

    pub fn init() !WindowManager {
        if (c.SDL_Init(c.SDL_INIT_VIDEO) != true) {
            std.log.err("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
            return error.SdlInitFailed;
        }
        return .{};
    }

    pub fn deinit(self: *WindowManager) void {
        for (0..self.windows.getCount()) |_| {
            const windowPtr = self.windows.getLastPtr();
            c.SDL_DestroyWindow(windowPtr.handle);
            self.windows.removeLast();
        }
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
        self.windows.set(@intCast(id), window);
        try self.changedWindows.append(self.windows.getPtr(@intCast(id)));
        self.openWindows += 1;
        std.debug.print("Window ID {} created\n", .{id});
    }

    pub fn showErrorBox(_: *WindowManager, title: [:0]const u8, message: [:0]const u8) void {
        _ = c.SDL_ShowSimpleMessageBox(c.SDL_MESSAGEBOX_ERROR, title.ptr, message.ptr, null);
    }

    pub fn cleanupWindows(self: *WindowManager) !void {
        for (self.changedWindows.slice()) |window| {
            if (window.status == .needDelete) try self.destroyWindow(window.id);
        }
        self.changedWindows.clear();
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

    fn destroyWindow(self: *WindowManager, id: u32) !void {
        const window = self.windows.get(@intCast(id));
        c.SDL_DestroyWindow(window.handle);
        self.windows.removeAtKey(@intCast(id));
    }

    pub fn processEvent(self: *WindowManager, event: *c.SDL_Event) !void {
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
                    },
                    c.SDL_EVENT_WINDOW_MINIMIZED => {
                        self.openWindows -= 1;
                        window.status = .needInactive;
                    },
                    c.SDL_EVENT_WINDOW_RESTORED => {
                        self.openWindows += 1;
                        window.status = .needActive;
                    },
                    c.SDL_EVENT_WINDOW_RESIZED => {
                        var newExtent: c.VkExtent2D = undefined;
                        _ = c.SDL_GetWindowSize(window.handle, @ptrCast(&newExtent.width), @ptrCast(&newExtent.height));
                        window.extent = newExtent;
                        window.status = .needUpdate;
                    },
                    else => {},
                }
                try self.changedWindows.append(window);
                std.debug.print("Status of Window {} now {s}\n", .{ id, @tagName(window.status) });
            },
            else => {},
        }
    }
};
