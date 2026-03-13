const TexId = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexId;
const WindowState = @import("../window/WindowState.zig").WindowData;
const InputData = @import("../input/InputData.zig").InputData;
const KeyEvent = @import("../input/InputSys.zig").KeyEvent;
const InputSys = @import("../input/InputSys.zig").InputSys;
const Window = @import("../window/Window.zig").Window;
const sdl = @import("../.modules/sdl.zig").c;
const vk = @import("../.modules/vk.zig").c;
const std = @import("std");

const MAX_WINDOWS = @import("../.configs/renderConfig.zig").MAX_WINDOWS;
const SDL_KEY_MAX = @import("../input/InputSys.zig").SDL_KEY_MAX;

const ImGuiMan = @import("../render/sys/ImGuiMan.zig").ImGuiMan;
const zgui = @import("zgui");

pub const WindowSys = struct {
    pub fn init(windowState: *WindowState) !void {
        if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != true) {
            std.log.err("SDL_Init failed: {s}\n", .{sdl.SDL_GetError()});
            return error.SdlInitFailed;
        }

        const windowProps = sdl.SDL_CreateProperties();
        if (windowProps == 0) {
            std.log.err("SDL_CreateProperties failed: {s}\n", .{sdl.SDL_GetError()});
            return error.WindowInitFailed;
        }
        windowState.windowProps = windowProps;
    }

    pub fn deinit(windowState: *WindowState) void {
        for (windowState.windows.getItems()) |*win| win.deinit();
        sdl.SDL_DestroyProperties(windowState.windowProps);
        sdl.SDL_Quit();
    }

    pub fn showAllWindows(windowState: *WindowState) void {
        for (windowState.windows.getItems()) |*win| win.show();
    }

    pub fn hideAllWindows(windowState: *WindowState) void {
        for (windowState.windows.getItems()) |*win| win.hide();
    }

    pub fn showOpacityAllWindows(windowState: *WindowState) void {
        for (windowState.windows.getItems()) |*win| win.setOpacity(1.0);
    }

    pub fn addWindow(windowState: *WindowState, title: [*c]const u8, w: c_int, h: c_int, renderTexId: TexId, x: c_int, y: c_int, resize: bool, texIds: []const TexId, camIndex: u8) !void {
        const props = windowState.windowProps;
        const flags = sdl.SDL_WINDOW_VULKAN | sdl.SDL_WINDOW_RESIZABLE | sdl.SDL_WINDOW_HIDDEN;
        _ = sdl.SDL_SetNumberProperty(props, sdl.SDL_PROP_WINDOW_CREATE_FLAGS_NUMBER, @intCast(flags));
        _ = sdl.SDL_SetNumberProperty(props, sdl.SDL_PROP_WINDOW_CREATE_X_NUMBER, @intCast(x));
        _ = sdl.SDL_SetNumberProperty(props, sdl.SDL_PROP_WINDOW_CREATE_Y_NUMBER, @intCast(y));
        _ = sdl.SDL_SetNumberProperty(props, sdl.SDL_PROP_WINDOW_CREATE_WIDTH_NUMBER, @intCast(w));
        _ = sdl.SDL_SetNumberProperty(props, sdl.SDL_PROP_WINDOW_CREATE_HEIGHT_NUMBER, @intCast(h));
        _ = sdl.SDL_SetStringProperty(props, sdl.SDL_PROP_WINDOW_CREATE_TITLE_STRING, title);

        var window = try Window.init(props, renderTexId, vk.VkExtent2D{ .width = @intCast(w), .height = @intCast(h) }, resize, texIds, camIndex);
        window.setOpacity(0.0);

        // window.setRelativeMouseMode(false);

        windowState.windows.upsert(window.id.val, window);
        try windowState.changedWindows.append(windowState.windows.getByKey(window.id.val));
        windowState.openWindows += 1;
        windowState.mainWindow = windowState.windows.getPtrByKey(window.id.val);
        std.debug.print("Window ID {} created to present Render ID {}\n", .{ window.id.val, renderTexId.val });
    }

    pub fn showErrorBox(title: [:0]const u8, message: [:0]const u8) void {
        _ = sdl.SDL_ShowSimpleMessageBox(sdl.SDL_MESSAGEBOX_ERROR, title.ptr, message.ptr, null);
    }

    pub fn getChangedWindows(windowState: *WindowState) []Window {
        return windowState.changedWindows.slice();
    }

    pub fn cleanupWindows(windowState: *WindowState) void {
        for (windowState.changedWindows.slice()) |tempWindow| {
            const actualWindow = windowState.windows.getPtrByKey(tempWindow.id.val);

            switch (tempWindow.state) {
                .needDelete => destroyWindow(windowState, actualWindow.id),
                .needUpdate, .needCreation => actualWindow.state = .active,
                .needActive => actualWindow.state = .active,
                .needInactive => actualWindow.state = .inactive,
                else => std.debug.print("WindowManager: Window {} State {s} should not need cleanup\n", .{ tempWindow.id.val, @tagName(tempWindow.state) }),
            }
        }
        windowState.changedWindows.clear();
    }

    pub fn toogleUiMode(windowState: *WindowState) void {
        if (windowState.uiActive == true) windowState.uiActive = false else windowState.uiActive = true;
        if (windowState.mainWindow) |window| window.setRelativeMouseMode(!windowState.uiActive);
    }

    pub fn pollEvents(windowState: *WindowState, inputState: *InputData, imguiMan: ?*ImGuiMan) !void {
        var event: sdl.SDL_Event = undefined;

        if (windowState.openWindows == 0) {
            if (sdl.SDL_WaitEvent(&event)) { // On pause wait for an event and process
                try processEvent(windowState, inputState, &event);
                if (windowState.uiActive == true) if (imguiMan) |im| im.processEvent(getEventWindowId(&event), &event);
            }
            while (sdl.SDL_PollEvent(&event)) { // drain remaining events
                try processEvent(windowState, inputState, &event);
                if (windowState.uiActive == true) if (imguiMan) |im| im.processEvent(getEventWindowId(&event), &event);
            }
        } else {
            while (sdl.SDL_PollEvent(&event)) { // When active process all events in queue
                try processEvent(windowState, inputState, &event);
                if (windowState.uiActive == true) if (imguiMan) |im| im.processEvent(getEventWindowId(&event), &event);
            }
        }
    }

    fn getEventWindowId(event: *sdl.SDL_Event) u32 {
        return switch (event.type) {
            sdl.SDL_EVENT_MOUSE_BUTTON_DOWN, sdl.SDL_EVENT_MOUSE_BUTTON_UP => event.button.windowID,
            sdl.SDL_EVENT_MOUSE_MOTION => event.motion.windowID,
            sdl.SDL_EVENT_MOUSE_WHEEL => event.wheel.windowID,
            sdl.SDL_EVENT_KEY_DOWN, sdl.SDL_EVENT_KEY_UP => event.key.windowID,
            sdl.SDL_EVENT_TEXT_INPUT => event.text.windowID,
            else => 0,
        };
    }

    fn destroyWindow(windowState: *WindowState, windowId: Window.WindowId) void {
        const window = windowState.windows.getByKey(windowId.val);
        window.deinit();
        windowState.windows.remove(windowId.val);
    }

    pub fn resetMainWindowOpacity(windowState: *WindowState) void {
        if (windowState.mainWindow) |window| {
            if (window.getOpacity() == 0) window.setOpacity(1.0);
        }
    }

    pub fn toggleMainFullscreen(windowState: *WindowState) void {
        if (windowState.mainWindow) |window| {
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

    pub fn processWindowEvent(windowState: *WindowState, event: *sdl.SDL_Event) !void {
        const id = event.window.windowID;
        var window = windowState.windows.getPtrByKey(id);

        switch (event.type) {
            sdl.SDL_EVENT_WINDOW_FOCUS_LOST => {
                std.debug.print("Main Window Lost\n", .{});
                window.setRelativeMouseMode(false);
                windowState.mainWindow = null;
                return; // Should not append window changes?
            },
            sdl.SDL_EVENT_WINDOW_FOCUS_GAINED => {
                std.debug.print("Main Window Set\n", .{});
                // const shouldBeRelative = if (self.uiActive == true) window.relativeMouse else false;
                window.setRelativeMouseMode(!windowState.uiActive);
                windowState.mainWindow = window;
                return; // Should not append window changes?
            },
            sdl.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED => { // Signaled for every pixel change if CPU isnt blocked
                std.debug.print("Window Pixel changed! \n", .{});
                return; // Should not append window changes?
            },
            sdl.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                if (window.getState() == .active) windowState.openWindows -= 1;
                window.setState(.needDelete);
            },
            sdl.SDL_EVENT_WINDOW_MINIMIZED => {
                windowState.openWindows -= 1;
                window.setState(.needInactive);
            },
            sdl.SDL_EVENT_WINDOW_RESTORED => {
                if (window.getState() == .active) return;
                windowState.openWindows += 1;
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
        try windowState.changedWindows.append(window.*);
        std.debug.print("State of Window {} now {s}\n", .{ id, @tagName(window.state) });
    }

    pub fn processEvent(windowState: *WindowState, inputState: *InputData, event: *sdl.SDL_Event) !void {
        switch (event.type) {
            sdl.SDL_EVENT_QUIT => {
                windowState.appExit = true;
            },
            sdl.SDL_EVENT_WINDOW_FOCUS_LOST,
            sdl.SDL_EVENT_WINDOW_FOCUS_GAINED,
            sdl.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED,
            sdl.SDL_EVENT_WINDOW_CLOSE_REQUESTED,
            sdl.SDL_EVENT_WINDOW_MINIMIZED,
            sdl.SDL_EVENT_WINDOW_RESTORED,
            sdl.SDL_EVENT_WINDOW_RESIZED,
            => try processWindowEvent(windowState, event),

            // Route to InputSys
            sdl.SDL_EVENT_MOUSE_BUTTON_DOWN,
            sdl.SDL_EVENT_MOUSE_BUTTON_UP,
            sdl.SDL_EVENT_KEY_DOWN,
            sdl.SDL_EVENT_KEY_UP,
            => processKeyEvent(inputState, event),

            sdl.SDL_EVENT_MOUSE_MOTION,
            => processMouseEvent(inputState, event),
            else => {},
        }
    }

    fn processKeyEvent(inputState: *InputData, event: *const sdl.SDL_Event) void {
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
        inputState.inputEvents.append(keyEvent) catch |err| std.debug.print("WindowManager: mouseButtonEvents append failed {}\n", .{err});
    }

    fn processMouseEvent(inputState: *InputData, event: *const sdl.SDL_Event) void {
        inputState.mouseMoveX += event.motion.xrel;
        inputState.mouseMoveY += event.motion.yrel;
    }
};
