const std = @import("std");
const c = @import("../c.zig");
const Window = @import("Window.zig").Window;
const Renderer = @import("../vulkan/Renderer.zig").Renderer;
const Swapchain = @import("../vulkan/SwapchainManager.zig").Swapchain;
const MemoryManger = @import("../core/MemoryManager.zig").MemoryManager;
const RenderPass = @import("../config.zig").RenderPass;
const CreateMapArray = @import("../structures/MapArray.zig").CreateMapArray;
const MAX_WINDOWS = @import("../config.zig").MAX_WINDOWS;
const SDL_KEY_MAX = @import("../core/EventManager.zig").SDL_KEY_MAX;

const KeyEvent = @import("../core/EventManager.zig").KeyEvent;
const MouseMovement = @import("../core/EventManager.zig").MouseMovement;

pub const WindowManager = struct {
    windows: CreateMapArray(Window, MAX_WINDOWS, u8, MAX_WINDOWS, 0) = .{},
    mainWindow: ?*Window = null,
    changedWindows: std.BoundedArray(*Window, MAX_WINDOWS) = .{},
    openWindows: u8 = 0,
    fullscreen: bool = false,
    close: bool = false,

    inputEvents: std.BoundedArray(KeyEvent, 127) = .{},
    mouseMovements: std.BoundedArray(MouseMovement, 63) = .{},

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

    pub fn addWindow(self: *WindowManager, title: [*c]const u8, width: c_int, height: c_int, renderPass: RenderPass) !void {
        const sdlHandle = c.SDL_CreateWindow(title, width, height, c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE) orelse {
            std.log.err("SDL_CreateWindow failed: {s}\n", .{c.SDL_GetError()});
            return error.WindowInitFailed;
        };
        const id = c.SDL_GetWindowID(sdlHandle);
        _ = c.SDL_SetWindowFullscreen(sdlHandle, false);
        _ = c.SDL_SetWindowRelativeMouseMode(sdlHandle, true);

        const window = try Window.init(id, sdlHandle, renderPass, c.VkExtent2D{ .width = @intCast(width), .height = @intCast(height) });
        self.windows.set(@intCast(id), window);
        try self.changedWindows.append(self.windows.getPtr(@intCast(id)));
        self.openWindows += 1;
        std.debug.print("Window ID {} for PipelineType {s} created\n", .{ id, @tagName(renderPass) });
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

    pub fn consumeKeyEvents(self: *WindowManager) []KeyEvent {
        defer self.inputEvents.clear();
        return self.inputEvents.slice();
    }
    pub fn consumeMouseMovements(self: *WindowManager) []MouseMovement {
        defer self.mouseMovements.clear();
        return self.mouseMovements.slice();
    }

    pub fn resetMainWindowOpacity(self: *WindowManager) void {
        if (self.mainWindow) |window| {
            const sdlHandle = window.*.handle;
            _ = c.SDL_SetWindowOpacity(sdlHandle, 1.0);
        }
    }

    pub fn toggleMainFullscreen(self: *WindowManager) void {
        if (self.mainWindow) |window| {
            const sdlHandle = window.*.handle;

            if (self.fullscreen == false) {
                _ = c.SDL_SetWindowBordered(sdlHandle, false);
                _ = c.SDL_SetWindowOpacity(sdlHandle, 0.0);
                _ = c.SDL_SetWindowFullscreen(sdlHandle, true);
                self.fullscreen = true;
            } else {
                _ = c.SDL_SetWindowBordered(sdlHandle, true);
                _ = c.SDL_SetWindowOpacity(sdlHandle, 0.0);
                _ = c.SDL_SetWindowFullscreen(sdlHandle, false);
                self.fullscreen = false;
            }
        }
    }

    pub fn processWindowEvent(self: *WindowManager, event: *c.SDL_Event) !void {
        const id = event.window.windowID;
        const window = self.windows.getPtr(@intCast(id));

        switch (event.type) {
            c.SDL_EVENT_WINDOW_FOCUS_LOST => {
                std.debug.print("Main Window Lost\n", .{});
                self.mainWindow = null;
                return; // Should not append window changes
            },
            c.SDL_EVENT_WINDOW_FOCUS_GAINED => {
                std.debug.print("Main Window Set\n", .{});
                self.mainWindow = self.windows.getPtr(@intCast(event.window.windowID));
                return; // Should not append window changes
            },
            c.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED => { // Ran for every pixel change if CPU isnt blocked
                std.debug.print("Window Pixel changed! \n", .{});
                return; // Should not append window changes
            },
            c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                if (window.status == .active) self.openWindows -= 1;
                window.status = .needDelete;
            },
            c.SDL_EVENT_WINDOW_MINIMIZED => {
                self.openWindows -= 1;
                window.status = .needInactive;
            },
            c.SDL_EVENT_WINDOW_RESTORED => {
                if (window.status == .active) return;
                self.openWindows += 1;
                window.status = .needActive;
            },
            c.SDL_EVENT_WINDOW_RESIZED => {
                var newExtent: c.VkExtent2D = undefined;
                _ = c.SDL_GetWindowSize(window.handle, @ptrCast(&newExtent.width), @ptrCast(&newExtent.height));
                window.extent = newExtent;
                window.status = .needUpdate;
            },
            else => {
                std.debug.print("Window Event {} could not be processed! \n", .{event.type});
                return;
            },
        }
        try self.changedWindows.append(window);
        std.debug.print("Status of Window {} now {s}\n", .{ id, @tagName(window.status) });
    }

    pub fn processKeyEvent(self: *WindowManager, event: *c.SDL_Event) void {
        var keyEvent: KeyEvent = undefined;

        switch (event.type) {
            c.SDL_EVENT_MOUSE_BUTTON_DOWN => keyEvent = .{ .key = @as(c_uint, event.button.button) + SDL_KEY_MAX, .event = .pressed },
            c.SDL_EVENT_MOUSE_BUTTON_UP => keyEvent = .{ .key = @as(c_uint, event.button.button) + SDL_KEY_MAX, .event = .released },
            c.SDL_EVENT_KEY_DOWN => keyEvent = .{ .key = event.key.scancode, .event = .pressed },
            c.SDL_EVENT_KEY_UP => keyEvent = .{ .key = event.key.scancode, .event = .released },
            else => {
                std.debug.print("Key Event {} could not be processed! \n", .{event.type});
                return;
            },
        }
        self.inputEvents.append(keyEvent) catch |err| {
            std.debug.print("WindowManager: mouseButtonEvents append failed {}\n", .{err});
        };
    }

    pub fn processEvent(self: *WindowManager, event: *c.SDL_Event) !void {
        switch (event.type) {
            c.SDL_EVENT_QUIT => {
                self.close = true;
            },
            c.SDL_EVENT_WINDOW_FOCUS_LOST,
            c.SDL_EVENT_WINDOW_FOCUS_GAINED,
            c.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED,
            c.SDL_EVENT_WINDOW_CLOSE_REQUESTED,
            c.SDL_EVENT_WINDOW_MINIMIZED,
            c.SDL_EVENT_WINDOW_RESTORED,
            c.SDL_EVENT_WINDOW_RESIZED,
            => try self.processWindowEvent(event),

            c.SDL_EVENT_MOUSE_BUTTON_DOWN,
            c.SDL_EVENT_MOUSE_BUTTON_UP,
            c.SDL_EVENT_KEY_DOWN,
            c.SDL_EVENT_KEY_UP,
            => self.processKeyEvent(event),

            c.SDL_EVENT_MOUSE_MOTION => {
                const mouseMovement = MouseMovement{ .xChange = event.motion.xrel, .yChange = event.motion.yrel };
                self.mouseMovements.append(mouseMovement) catch |err| {
                    std.debug.print("WindowManager: mouseMovements append failed {}\n", .{err});
                };
            },
            else => {},
        }
    }
};
