const TexId = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexId;
const RendererQueue = @import("../render/RendererQueue.zig").RendererQueue;
const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;
const ViewportId = @import("../viewport/ViewportSys.zig").ViewportId;
const InputQueue = @import("../input/InputQueue.zig").InputQueue;
const EngineData = @import("../EngineData.zig").EngineData;
const WindowQueue = @import("WindowQueue.zig").WindowQueue;
const KeyEvent = @import("../input/InputSys.zig").KeyEvent;
const InputSys = @import("../input/InputSys.zig").InputSys;
const WindowData = @import("WindowData.zig").WindowData;
const Window = @import("../window/Window.zig").Window;
const ig = @cImport(@cInclude("imgui_ctx.h"));
const sdl = @import("../.modules/sdl.zig").c;
const vk = @import("../.modules/vk.zig").c;
const zgui = @import("zgui");
const std = @import("std");
const SDL_KEY_MAX = @import("../input/InputSys.zig").SDL_KEY_MAX;

pub const WindowSys = struct {
    pub fn init(windowState: *WindowData) !void {
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

    pub fn deinit(windowData: *WindowData) void {
        for (windowData.windows.getItems()) |*win| win.deinit();
        sdl.SDL_DestroyProperties(windowData.windowProps);
        sdl.SDL_Quit();
    }

    pub fn update(windowData: *WindowData, state: *const EngineData, windowQueue: *WindowQueue, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        for (windowData.hiddenWindows.constSlice()) |windowId| {
            const hiddenWindow = windowData.windows.getPtrByKey(windowId.val);
            hiddenWindow.show();
            hiddenWindow.setOpacity(1.0);
        }
        windowData.hiddenWindows.clear();

        for (windowQueue.get()) |windowEvent| {
            switch (windowEvent) {
                .addWindow => |inf| try addWindow(windowData, inf.title, inf.w, inf.h, inf.renderTexId, inf.x, inf.y, inf.resize, inf.texIds, inf.viewIds),
            }
        }
        windowQueue.clear();

        try if (state.input.toggleFullscreen) toggleMainFullscreen(windowData);
        if (state.input.toggleImgui) toogleUiMode(windowData);

        const changedWindows = getChangedWindows(windowData);
        for (changedWindows) |changedWindow| {
            const updatedWindowPtr = try memoryMan.arena.allocator().create(Window);
            updatedWindowPtr.* = changedWindow;
            rendererQueue.append(.{ .updateWindowState = updatedWindowPtr });
        }

        cleanupWindows(windowData);
    }

    pub fn updateActiveWindows(windowData: *WindowData) !void {
        windowData.activeWindows.clear();
        for (windowData.windows.getConstItems()) |*window| {
            if (window.state == .active) try windowData.activeWindows.append(window.*);
        }
    }

    fn addWindow(windowData: *WindowData, title: [*c]const u8, w: c_int, h: c_int, renderTexId: TexId, x: c_int, y: c_int, resize: bool, texIds: []const TexId, viewIds: [4]?ViewportId) !void {
        const props = windowData.windowProps;
        const flags = sdl.SDL_WINDOW_VULKAN | sdl.SDL_WINDOW_RESIZABLE | sdl.SDL_WINDOW_HIDDEN; // | sdl.SDL_WINDOW_BORDERLESS
        _ = sdl.SDL_SetNumberProperty(props, sdl.SDL_PROP_WINDOW_CREATE_FLAGS_NUMBER, @intCast(flags));
        _ = sdl.SDL_SetNumberProperty(props, sdl.SDL_PROP_WINDOW_CREATE_X_NUMBER, @intCast(x));
        _ = sdl.SDL_SetNumberProperty(props, sdl.SDL_PROP_WINDOW_CREATE_Y_NUMBER, @intCast(y));
        _ = sdl.SDL_SetNumberProperty(props, sdl.SDL_PROP_WINDOW_CREATE_WIDTH_NUMBER, @intCast(w));
        _ = sdl.SDL_SetNumberProperty(props, sdl.SDL_PROP_WINDOW_CREATE_HEIGHT_NUMBER, @intCast(h));
        _ = sdl.SDL_SetStringProperty(props, sdl.SDL_PROP_WINDOW_CREATE_TITLE_STRING, title);

        var window = try Window.init(props, renderTexId, vk.VkExtent2D{ .width = @intCast(w), .height = @intCast(h) }, resize, texIds, viewIds);
        window.setOpacity(0.0);

        // window.setRelativeMouseMode(false);

        windowData.windows.upsert(window.id.val, window);
        try windowData.changedWindows.append(windowData.windows.getByKey(window.id.val));
        windowData.openWindows += 1;
        windowData.mainWindow = windowData.windows.getPtrByKey(window.id.val);
        try windowData.hiddenWindows.append(window.id);
        std.debug.print("Window ID {} created to present Render ID {}\n", .{ window.id.val, renderTexId.val });
    }

    pub fn showErrorBox(title: [:0]const u8, message: [:0]const u8) void {
        _ = sdl.SDL_ShowSimpleMessageBox(sdl.SDL_MESSAGEBOX_ERROR, title.ptr, message.ptr, null);
    }

    fn getChangedWindows(windowData: *WindowData) []Window {
        return windowData.changedWindows.slice();
    }

    fn cleanupWindows(windowData: *WindowData) void {
        for (windowData.changedWindows.slice()) |tempWindow| {
            const actualWindow = windowData.windows.getPtrByKey(tempWindow.id.val);

            switch (tempWindow.state) {
                .needDelete => destroyWindow(windowData, actualWindow.id),
                .needUpdate, .needCreation => actualWindow.state = .active,
                .needActive => actualWindow.state = .active,
                .needInactive => actualWindow.state = .inactive,
                else => std.debug.print("WindowManager: Window {} State {s} should not need cleanup\n", .{ tempWindow.id.val, @tagName(tempWindow.state) }),
            }
        }
        windowData.changedWindows.clear();
    }

    fn toogleUiMode(windowData: *WindowData) void {
        if (windowData.uiActive == true) windowData.uiActive = false else windowData.uiActive = true;
        if (windowData.mainWindow) |window| window.setRelativeMouseMode(!windowData.uiActive);
        std.debug.print("WindowSys: UI Toggle {}\n", .{windowData.uiActive});
    }

    pub fn pollEvents(data: *const EngineData, windowData: *WindowData, inputQueue: *InputQueue) !void {
        var event: sdl.SDL_Event = undefined;

        if (windowData.openWindows == 0) {
            if (sdl.SDL_WaitEvent(&event)) { // On pause wait for an event and process
                try processEvent(windowData, inputQueue, &event);
                if (windowData.uiActive == true) processGuiEvent(getEventWindowId(&event), &event, data);
            }
            while (sdl.SDL_PollEvent(&event)) { // drain remaining events
                try processEvent(windowData, inputQueue, &event);
                if (windowData.uiActive == true) processGuiEvent(getEventWindowId(&event), &event, data);
            }
        } else {
            while (sdl.SDL_PollEvent(&event)) { // When active process all events in queue
                try processEvent(windowData, inputQueue, &event);
                if (windowData.uiActive == true) processGuiEvent(getEventWindowId(&event), &event, data);
            }
        }
    }

    fn processGuiEvent(windowId: u32, event: *const sdl.SDL_Event, data: *const EngineData) void {
        if (!data.ui.initialized or !data.ui.contexts.isKeyUsed(windowId)) return;

        var targetId = windowId;
        if (windowId == 0) { // Global Events pushed to main Window ?
            if (data.window.mainWindow) |mainWindow| {
                targetId = mainWindow.id.val;
            } else return;
        }

        const ctx = data.ui.contexts.getByKey(windowId);
        ig.igui_set_current_context(@ptrCast(ctx));
        _ = zgui.backend.processEvent(event);
    }

    fn getEventWindowId(event: *sdl.SDL_Event) u32 {
        return switch (event.type) {
            sdl.SDL_EVENT_MOUSE_BUTTON_DOWN, sdl.SDL_EVENT_MOUSE_BUTTON_UP => event.button.windowID,
            sdl.SDL_EVENT_MOUSE_MOTION => event.motion.windowID,
            sdl.SDL_EVENT_MOUSE_WHEEL => event.wheel.windowID,
            sdl.SDL_EVENT_KEY_DOWN, sdl.SDL_EVENT_KEY_UP => event.key.windowID,
            sdl.SDL_EVENT_TEXT_INPUT => event.text.windowID,

            sdl.SDL_EVENT_WINDOW_FOCUS_LOST,
            sdl.SDL_EVENT_WINDOW_FOCUS_GAINED,
            sdl.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED,
            sdl.SDL_EVENT_WINDOW_CLOSE_REQUESTED,
            sdl.SDL_EVENT_WINDOW_MINIMIZED,
            sdl.SDL_EVENT_WINDOW_RESTORED,
            sdl.SDL_EVENT_WINDOW_RESIZED,
            => event.window.windowID,
            else => 0,
        };
    }

    fn destroyWindow(windowData: *WindowData, windowId: Window.WindowId) void {
        const window = windowData.windows.getByKey(windowId.val);
        window.deinit();
        windowData.windows.remove(windowId.val);
    }

    fn toggleMainFullscreen(windowData: *WindowData) !void {
        if (windowData.mainWindow) |window| {
            window.setOpacity(0);
            // window.hide();

            if (window.isFullscreen() == false) {
                // window.setBordered(false);
                window.setFullscreenBorderless(true);
                std.debug.print("MAIN FULLSCREEN ON\n", .{});
            } else {
                window.setFullscreenBorderless(false);
                // window.setBordered(true);
                std.debug.print("MAIN FULLSCREEN OFF\n", .{});
            }
            // window.setOpacity(1.0);
            // window.show();
            try windowData.hiddenWindows.append(window.id);
        }
    }

    fn processWindowEvent(windowData: *WindowData, event: *sdl.SDL_Event) !void {
        const id = event.window.windowID;

        if (!windowData.windows.isKeyUsed(id)) return;

        var window = windowData.windows.getPtrByKey(id);

        switch (event.type) {
            sdl.SDL_EVENT_WINDOW_FOCUS_LOST => {
                std.debug.print("Main Window Lost\n", .{});
                window.setRelativeMouseMode(false);
                windowData.mainWindow = null;
                return; // Should not append window changes?
            },
            sdl.SDL_EVENT_WINDOW_FOCUS_GAINED => {
                std.debug.print("Main Window Set\n", .{});
                // const shouldBeRelative = if (self.uiActive == true) window.relativeMouse else false;
                window.setRelativeMouseMode(!windowData.uiActive);
                windowData.mainWindow = window;
                return; // Should not append window changes?
            },
            sdl.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED => { // Signaled for every pixel change if CPU isnt blocked
                std.debug.print("Window Pixel changed! \n", .{});
                return; // Should not append window changes?
            },
            sdl.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
                if (window.getState() == .active) windowData.openWindows -= 1;
                window.hide();
                window.setState(.needDelete);
            },
            sdl.SDL_EVENT_WINDOW_MINIMIZED => {
                windowData.openWindows -= 1;
                window.setState(.needInactive);
            },
            sdl.SDL_EVENT_WINDOW_RESTORED => {
                if (window.getState() == .active) return;
                windowData.openWindows += 1;
                window.setState(.needActive);
            },
            sdl.SDL_EVENT_WINDOW_RESIZED => {
                window.extent = window.getPixelExtent();
                window.setState(.needUpdate);
            },
            else => {
                std.debug.print("Window Event {} could not be processed! \n", .{event.type});
                return;
            },
        }
        try windowData.changedWindows.append(window.*);
        std.debug.print("State of Window {} now {s}\n", .{ id, @tagName(window.state) });
    }

    fn processEvent(windowData: *WindowData, inputQueue: *InputQueue, event: *sdl.SDL_Event) !void {
        switch (event.type) {
            sdl.SDL_EVENT_QUIT => {
                windowData.appExit = true;
            },
            sdl.SDL_EVENT_WINDOW_FOCUS_LOST,
            sdl.SDL_EVENT_WINDOW_FOCUS_GAINED,
            sdl.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED,
            sdl.SDL_EVENT_WINDOW_CLOSE_REQUESTED,
            sdl.SDL_EVENT_WINDOW_MINIMIZED,
            sdl.SDL_EVENT_WINDOW_RESTORED,
            sdl.SDL_EVENT_WINDOW_RESIZED,
            => try processWindowEvent(windowData, event),

            // Route to InputSys
            sdl.SDL_EVENT_MOUSE_BUTTON_DOWN,
            sdl.SDL_EVENT_MOUSE_BUTTON_UP,
            sdl.SDL_EVENT_KEY_DOWN,
            sdl.SDL_EVENT_KEY_UP,
            => processKeyEvent(inputQueue, event),

            sdl.SDL_EVENT_MOUSE_MOTION,
            => processMouseEvent(inputQueue, event),
            else => {},
        }
    }

    fn processKeyEvent(inputQueue: *InputQueue, event: *const sdl.SDL_Event) void {
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
        inputQueue.append(.{ .keyEvent = keyEvent });
    }

    fn processMouseEvent(inputQueue: *InputQueue, event: *const sdl.SDL_Event) void {
        inputQueue.append(.{ .mouseMove = .{ .x = event.motion.xrel, .y = event.motion.yrel } });
    }
};
