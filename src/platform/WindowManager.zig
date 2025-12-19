const std = @import("std");
const sdl = @import("../modules/sdl.zig").c;
const vk = @import("../modules/vk.zig").c;
const Window = @import("Window.zig").Window;
const KeyEvent = @import("../core/EventManager.zig").KeyEvent;
const MouseMovement = @import("../core/EventManager.zig").MouseMovement;
const CreateMapArray = @import("../structures/MapArray.zig").CreateMapArray;
const FixedList = @import("../structures/FixedList.zig").FixedList;
const MAX_WINDOWS = @import("../configs/renderConfig.zig").MAX_WINDOWS;
const SDL_KEY_MAX = @import("../core/EventManager.zig").SDL_KEY_MAX;

pub const WindowManager = struct {
    windows: CreateMapArray(Window, MAX_WINDOWS, u32, MAX_WINDOWS, 0) = .{},
    mainWindow: ?*Window = null,
    changedWindows: FixedList(*Window, MAX_WINDOWS) = .{},
    openWindows: u8 = 0,
    fullscreen: bool = false,
    appExit: bool = false,

    inputEvents: FixedList(KeyEvent, 127) = .{},
    mouseMovements: FixedList(MouseMovement, 63) = .{},

    pub fn init() !WindowManager {
        if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != true) {
            std.log.err("SDL_Init failed: {s}\n", .{sdl.SDL_GetError()});
            return error.SdlInitFailed;
        }
        return .{};
    }

    pub fn deinit(self: *WindowManager) void {
        for (0..self.windows.getCount()) |_| {
            const windowPtr = self.windows.getLastPtr();
            sdl.SDL_DestroyWindow(windowPtr.handle);
            self.windows.removeLast();
        }
        sdl.SDL_Quit();
    }

    pub fn addWindow(self: *WindowManager, title: [*c]const u8, width: c_int, height: c_int, renderId: u8, xPos: c_int, yPos: c_int) !void {
        const sdlHandle = sdl.SDL_CreateWindow(title, width, height, sdl.SDL_WINDOW_VULKAN | sdl.SDL_WINDOW_RESIZABLE) orelse {
            std.log.err("SDL_CreateWindow failed: {s}\n", .{sdl.SDL_GetError()});
            return error.WindowInitFailed;
        };
        const windowId = sdl.SDL_GetWindowID(sdlHandle);
        _ = sdl.SDL_SetWindowFullscreen(sdlHandle, false);
        _ = sdl.SDL_SetWindowRelativeMouseMode(sdlHandle, true);
        _ = sdl.SDL_SetWindowPosition(sdlHandle, xPos, yPos);

        const window = try Window.init(windowId, sdlHandle, renderId, vk.VkExtent2D{ .width = @intCast(width), .height = @intCast(height) });
        self.windows.set(windowId, window);
        try self.changedWindows.append(self.windows.getPtr(windowId));
        self.openWindows += 1;
        std.debug.print("Window ID {} created to present Render ID {}\n", .{ windowId, renderId });
    }

    pub fn showErrorBox(_: *WindowManager, title: [:0]const u8, message: [:0]const u8) void {
        _ = sdl.SDL_ShowSimpleMessageBox(sdl.SDL_MESSAGEBOX_ERROR, title.ptr, message.ptr, null);
    }

    pub fn getChangedWindows(self: *WindowManager) []*Window {
        return self.changedWindows.slice();
    }

    pub fn cleanupWindows(self: *WindowManager) void {
        for (self.changedWindows.slice()) |window| {
            switch (window.state) {
                .needDelete => self.destroyWindow(window.windowId),
                .needUpdate, .needCreation => window.state = .active,
                .needActive => window.state = .active,
                .needInactive => window.state = .inactive,
                else => std.debug.print("WindowManager: Window {} State {s} should not need cleanup\n", .{ window.windowId, @tagName(window.state) }),
            }
        }
        self.changedWindows.clear();
    }

    pub fn pollEvents(self: *WindowManager) !void {
        var event: sdl.SDL_Event = undefined;

        if (self.openWindows == 0) {
            if (sdl.SDL_WaitEvent(&event)) try self.processEvent(&event); // On pause wait for an event and process
            while (sdl.SDL_PollEvent(&event)) try self.processEvent(&event); // drain remaining events
        } else {
            while (sdl.SDL_PollEvent(&event)) try self.processEvent(&event); // When active process all events in queue
        }
    }

    fn destroyWindow(self: *WindowManager, windowId: u32) void {
        const window = self.windows.get(windowId);
        sdl.SDL_DestroyWindow(window.handle);
        self.windows.removeAtKey(windowId);
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
            _ = sdl.SDL_SetWindowOpacity(sdlHandle, 1.0);
        }
    }

    pub fn toggleMainFullscreen(self: *WindowManager) void {
        if (self.mainWindow) |window| {
            const sdlHandle = window.*.handle;

            if (self.fullscreen == false) {
                _ = sdl.SDL_SetWindowBordered(sdlHandle, false);
                _ = sdl.SDL_SetWindowOpacity(sdlHandle, 0.0);
                _ = sdl.SDL_SetWindowFullscreen(sdlHandle, true);
                self.fullscreen = true;
            } else {
                _ = sdl.SDL_SetWindowBordered(sdlHandle, true);
                _ = sdl.SDL_SetWindowOpacity(sdlHandle, 0.0);
                _ = sdl.SDL_SetWindowFullscreen(sdlHandle, false);
                self.fullscreen = false;
            }
        }
    }

    pub fn processWindowEvent(self: *WindowManager, event: *sdl.SDL_Event) !void {
        const id = event.window.windowID;
        const window = self.windows.getPtr(id);

        switch (event.type) {
            sdl.SDL_EVENT_WINDOW_FOCUS_LOST => {
                std.debug.print("Main Window Lost\n", .{});
                self.mainWindow = null;
                return; // Should not append window changes
            },
            sdl.SDL_EVENT_WINDOW_FOCUS_GAINED => {
                std.debug.print("Main Window Set\n", .{});
                self.mainWindow = self.windows.getPtr(event.window.windowID);
                return; // Should not append window changes
            },
            sdl.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED => { // Ran for every pixel change if CPU isnt blocked
                std.debug.print("Window Pixel changed! \n", .{});
                return; // Should not append window changes
            },
            sdl.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                if (window.state == .active) self.openWindows -= 1;
                window.state = .needDelete;
            },
            sdl.SDL_EVENT_WINDOW_MINIMIZED => {
                self.openWindows -= 1;
                window.state = .needInactive;
            },
            sdl.SDL_EVENT_WINDOW_RESTORED => {
                if (window.state == .active) return;
                self.openWindows += 1;
                window.state = .needActive;
            },
            sdl.SDL_EVENT_WINDOW_RESIZED => {
                var newExtent: vk.VkExtent2D = undefined;
                _ = sdl.SDL_GetWindowSize(window.handle, @ptrCast(&newExtent.width), @ptrCast(&newExtent.height));
                window.extent = newExtent;
                window.state = .needUpdate;
            },
            else => {
                std.debug.print("Window Event {} could not be processed! \n", .{event.type});
                return;
            },
        }
        try self.changedWindows.append(window);
        std.debug.print("State of Window {} now {s}\n", .{ id, @tagName(window.state) });
    }

    pub fn processKeyEvent(self: *WindowManager, event: *sdl.SDL_Event) void {
        var keyEvent: KeyEvent = undefined;

        switch (event.type) {
            sdl.SDL_EVENT_MOUSE_BUTTON_DOWN => keyEvent = .{ .key = @as(c_uint, event.button.button) + SDL_KEY_MAX, .event = .pressed },
            sdl.SDL_EVENT_MOUSE_BUTTON_UP => keyEvent = .{ .key = @as(c_uint, event.button.button) + SDL_KEY_MAX, .event = .released },
            sdl.SDL_EVENT_KEY_DOWN => keyEvent = .{ .key = event.key.scancode, .event = .pressed },
            sdl.SDL_EVENT_KEY_UP => keyEvent = .{ .key = event.key.scancode, .event = .released },
            else => {
                std.debug.print("Key Event {} could not be processed! \n", .{event.type});
                return;
            },
        }
        self.inputEvents.append(keyEvent) catch |err| {
            std.debug.print("WindowManager: mouseButtonEvents append failed {}\n", .{err});
        };
    }

    pub fn processEvent(self: *WindowManager, event: *sdl.SDL_Event) !void {
        switch (event.type) {
            sdl.SDL_EVENT_QUIT => {
                self.appExit = true;
            },
            sdl.SDL_EVENT_WINDOW_FOCUS_LOST,
            sdl.SDL_EVENT_WINDOW_FOCUS_GAINED,
            sdl.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED,
            sdl.SDL_EVENT_WINDOW_CLOSE_REQUESTED,
            sdl.SDL_EVENT_WINDOW_MINIMIZED,
            sdl.SDL_EVENT_WINDOW_RESTORED,
            sdl.SDL_EVENT_WINDOW_RESIZED,
            => try self.processWindowEvent(event),

            sdl.SDL_EVENT_MOUSE_BUTTON_DOWN,
            sdl.SDL_EVENT_MOUSE_BUTTON_UP,
            sdl.SDL_EVENT_KEY_DOWN,
            sdl.SDL_EVENT_KEY_UP,
            => self.processKeyEvent(event),

            sdl.SDL_EVENT_MOUSE_MOTION => {
                const mouseMovement = MouseMovement{ .xChange = event.motion.xrel, .yChange = event.motion.yrel };
                self.mouseMovements.append(mouseMovement) catch |err| {
                    std.debug.print("WindowManager: mouseMovements append failed {}\n", .{err});
                };
            },
            else => {},
        }
    }
};
