const TexId = @import("../vulkan/types/res/TextureMeta.zig").TextureMeta.TexId;
const MouseMovement = @import("../core/EventManager.zig").MouseMovement;
const FixedList = @import("../structures/FixedList.zig").FixedList;
const LinkedMap = @import("../structures/LinkedMap.zig").LinkedMap;
const KeyEvent = @import("../core/EventManager.zig").KeyEvent;
const Window = @import("Window.zig").Window;
const sdl = @import("../modules/sdl.zig").c;
const vk = @import("../modules/vk.zig").c;
const std = @import("std");
const MAX_WINDOWS = @import("../configs/renderConfig.zig").MAX_WINDOWS;
const SDL_KEY_MAX = @import("../core/EventManager.zig").SDL_KEY_MAX;

const ImGuiMan = @import("../vulkan/sys/ImGuiMan.zig").ImGuiMan;
const zgui = @import("zgui");

pub const WindowManager = struct {
    windows: LinkedMap(Window, MAX_WINDOWS, u32, 32 + MAX_WINDOWS, 0) = .{},
    mainWindow: ?*Window = null,
    changedWindows: FixedList(Window, MAX_WINDOWS) = .{},
    openWindows: u8 = 0,
    appExit: bool = false,
    windowProps: sdl.SDL_PropertiesID,
    uiActive: bool = false,

    inputEvents: FixedList(KeyEvent, 127) = .{},
    mouseMoveX: f32 = 0,
    mouseMoveY: f32 = 0,

    pub fn init() !WindowManager {
        if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != true) {
            std.log.err("SDL_Init failed: {s}\n", .{sdl.SDL_GetError()});
            return error.SdlInitFailed;
        }

        const windowProps = sdl.SDL_CreateProperties();
        if (windowProps == 0) {
            std.log.err("SDL_CreateProperties failed: {s}\n", .{sdl.SDL_GetError()});
            return error.WindowInitFailed;
        }
        return .{ .windowProps = windowProps };
    }

    pub fn deinit(self: *WindowManager) void {
        for (self.windows.getItems()) |*win| win.deinit();
        sdl.SDL_DestroyProperties(self.windowProps);
        sdl.SDL_Quit();
    }

    pub fn showAllWindows(self: *WindowManager) void {
        for (self.windows.getItems()) |*win| win.show();
    }

    pub fn hideAllWindows(self: *WindowManager) void {
        for (self.windows.getItems()) |*win| win.hide();
    }

    pub fn showOpacityAllWindows(self: *WindowManager) void {
        for (self.windows.getItems()) |*win| win.setOpacity(1.0);
    }

    pub fn addWindow(self: *WindowManager, title: [*c]const u8, width: c_int, height: c_int, renderTexId: TexId, xPos: c_int, yPos: c_int, resizeTex: bool, linkedTexIds: []const TexId) !void {
        const props = self.windowProps;
        const flags = sdl.SDL_WINDOW_VULKAN | sdl.SDL_WINDOW_RESIZABLE | sdl.SDL_WINDOW_HIDDEN;
        _ = sdl.SDL_SetNumberProperty(props, sdl.SDL_PROP_WINDOW_CREATE_FLAGS_NUMBER, @intCast(flags));
        _ = sdl.SDL_SetNumberProperty(props, sdl.SDL_PROP_WINDOW_CREATE_X_NUMBER, @intCast(xPos));
        _ = sdl.SDL_SetNumberProperty(props, sdl.SDL_PROP_WINDOW_CREATE_Y_NUMBER, @intCast(yPos));
        _ = sdl.SDL_SetNumberProperty(props, sdl.SDL_PROP_WINDOW_CREATE_WIDTH_NUMBER, @intCast(width));
        _ = sdl.SDL_SetNumberProperty(props, sdl.SDL_PROP_WINDOW_CREATE_HEIGHT_NUMBER, @intCast(height));
        _ = sdl.SDL_SetStringProperty(props, sdl.SDL_PROP_WINDOW_CREATE_TITLE_STRING, title);

        const window = try Window.init(props, renderTexId, vk.VkExtent2D{ .width = @intCast(width), .height = @intCast(height) }, resizeTex, linkedTexIds);
        window.setOpacity(0.0);

        //window.setRelativeMouseMode(true);

        self.windows.upsert(window.id.val, window);
        try self.changedWindows.append(self.windows.getByKey(window.id.val));
        self.openWindows += 1;
        self.mainWindow = self.windows.getPtrByKey(window.id.val);
        std.debug.print("Window ID {} created to present Render ID {}\n", .{ window.id.val, renderTexId.val });
    }

    pub fn showErrorBox(_: *WindowManager, title: [:0]const u8, message: [:0]const u8) void {
        _ = sdl.SDL_ShowSimpleMessageBox(sdl.SDL_MESSAGEBOX_ERROR, title.ptr, message.ptr, null);
    }

    pub fn getChangedWindows(self: *WindowManager) []Window {
        return self.changedWindows.slice();
    }

    pub fn cleanupWindows(self: *WindowManager) void {
        for (self.changedWindows.slice()) |tempWindow| {
            const actualWindow = self.windows.getPtrByKey(tempWindow.id.val);

            switch (tempWindow.state) {
                .needDelete => self.destroyWindow(actualWindow.id),
                .needUpdate, .needCreation => actualWindow.state = .active,
                .needActive => actualWindow.state = .active,
                .needInactive => actualWindow.state = .inactive,
                else => std.debug.print("WindowManager: Window {} State {s} should not need cleanup\n", .{ tempWindow.id.val, @tagName(tempWindow.state) }),
            }
        }
        self.changedWindows.clear();
    }

    pub fn toogleUiMode(self: *WindowManager) void {
        if (self.uiActive == true) self.uiActive = false else self.uiActive = true;
        if (self.mainWindow) |window| window.setRelativeMouseMode(!self.uiActive);
    }

    pub fn pollEvents(self: *WindowManager) !void {
        var event: sdl.SDL_Event = undefined;

        if (self.openWindows == 0) {
            if (sdl.SDL_WaitEvent(&event)) { // On pause wait for an event and process
                try self.processEvent(&event);
                if (self.uiActive == true) _ = zgui.backend.processEvent(&event);
            }
            while (sdl.SDL_PollEvent(&event)) { // drain remaining events
                try self.processEvent(&event);
                if (self.uiActive == true) _ = zgui.backend.processEvent(&event);
            }
        } else {
            while (sdl.SDL_PollEvent(&event)) { // When active process all events in queue
                try self.processEvent(&event);
                if (self.uiActive == true) _ = zgui.backend.processEvent(&event);
            }
        }
    }

    fn destroyWindow(self: *WindowManager, windowId: Window.WindowId) void {
        const window = self.windows.getByKey(windowId.val);
        window.deinit();
        self.windows.remove(windowId.val);
    }

    pub fn consumeKeyEvents(self: *WindowManager) []KeyEvent {
        defer self.inputEvents.clear();
        return self.inputEvents.slice();
    }
    pub fn consumeMouseMovements(self: *WindowManager) []MouseMovement {
        defer self.mouseMoves.clear();
        return self.mouseMoves.slice();
    }

    pub fn resetMainWindowOpacity(self: *WindowManager) void {
        if (self.mainWindow) |window| {
            if (window.getOpacity() == 0) window.setOpacity(1.0);
        }
    }

    pub fn toggleMainFullscreen(self: *WindowManager) void {
        if (self.mainWindow) |window| {
            if (window.isFullscreen() == false) {
                // window.setBordered(false);
                window.setOpacity(0);
                window.setFullscreenBorderless(true);
            } else {
                // window.setBordered(true);
                window.setOpacity(0);
                window.setFullscreenBorderless(false);
            }
            window.setOpacity(1.0);
        }
    }

    pub fn processWindowEvent(self: *WindowManager, event: *sdl.SDL_Event) !void {
        const id = event.window.windowID;
        const window = self.windows.getPtrByKey(id);

        switch (event.type) {
            sdl.SDL_EVENT_WINDOW_FOCUS_LOST => {
                std.debug.print("Main Window Lost\n", .{});
                self.mainWindow = null;
                return; // Should not append window changes?
            },
            sdl.SDL_EVENT_WINDOW_FOCUS_GAINED => {
                std.debug.print("Main Window Set\n", .{});
                self.mainWindow = window;
                return; // Should not append window changes?
            },
            sdl.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED => { // Signaled for every pixel change if CPU isnt blocked
                std.debug.print("Window Pixel changed! \n", .{});
                return; // Should not append window changes?
            },
            sdl.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                if (window.getState() == .active) self.openWindows -= 1;
                window.setState(.needDelete);
            },
            sdl.SDL_EVENT_WINDOW_MINIMIZED => {
                self.openWindows -= 1;
                window.setState(.needInactive);
            },
            sdl.SDL_EVENT_WINDOW_RESTORED => {
                if (window.getState() == .active) return;
                self.openWindows += 1;
                window.setState(.needActive);
            },
            sdl.SDL_EVENT_WINDOW_RESIZED => {
                window.extent = window.getExtent();
                window.setState(.needUpdate);
            },
            else => {
                std.debug.print("Window Event {} could not be processed! \n", .{event.type});
                return;
            },
        }
        try self.changedWindows.append(window.*);
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
                self.mouseMoveX += event.motion.xrel;
                self.mouseMoveY += event.motion.yrel;
            },
            else => {},
        }
    }
};
