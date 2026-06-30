const ViewportId = @import("../.configs/idConfig.zig").ViewportId;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const WindowId = @import("../.configs/idConfig.zig").WindowId;
const rc = @import("../.configs/renderConfig.zig");
const sdl = @import("../.modules/sdl.zig").c;
const vk = @import("../.modules/vk.zig").c;
const std = @import("std");

pub const Window = struct {
    pub const WindowState = enum { active, inactive, needCreation, needUpdate, needDelete, needInactive, needActive };
    name: []const u8,
    handle: *sdl.SDL_Window,
    state: WindowState = .needCreation,
    extent: vk.VkExtent2D,
    id: WindowId,
    resizeTex: bool,
    relativeMouse: bool = false,
    viewIds: [4]?ViewportId = .{null} ** 4,

    pub fn init(windowProps: sdl.SDL_PropertiesID, extent: vk.VkExtent2D, resizeTex: bool, viewIds: [4]?ViewportId, name: []const u8) !Window {
        const winHandle = sdl.SDL_CreateWindowWithProperties(windowProps) orelse {
            std.log.err("SDL_CreateWindowWithProperties failed: {s}\n", .{sdl.SDL_GetError()});
            return error.WindowInitFailed;
        };
        const windowId = sdl.SDL_GetWindowID(winHandle);

        var window = Window{
            .name = name,
            .handle = winHandle,
            .extent = extent,
            .id = .id(windowId),
            .resizeTex = resizeTex,
            .viewIds = viewIds,
        };

        window.extent = window.getPixelExtent();
        return window;
    }

    pub fn deinit(self: *const Window) void {
        sdl.SDL_DestroyWindow(self.handle);
    }

    pub fn getState(self: *Window) WindowState {
        return self.state;
    }

    pub fn setState(self: *Window, state: WindowState) void {
        self.state = state;
    }

    pub fn show(self: *const Window) void {
        _ = sdl.SDL_ShowWindow(self.handle);
    }

    pub fn hide(self: *const Window) void {
        _ = sdl.SDL_HideWindow(self.handle);
    }

    pub fn setOpacity(self: *const Window, val: f32) void {
        _ = sdl.SDL_SetWindowOpacity(self.handle, val);
    }

    pub fn minimize(self: *const Window) void {
        _ = sdl.SDL_MinimizeWindow(self.handle);
    }

    pub fn maximize(self: *const Window) void {
        _ = sdl.SDL_MaximizeWindow(self.handle);
    }

    pub fn restore(self: *const Window) void {
        _ = sdl.SDL_RestoreWindow(self.handle);
    }

    pub fn getOpacity(self: *const Window) u32 {
        return sdl.SDL_GetWindowOpacity(self.handle);
    }

    pub fn setBordered(self: *const Window, val: bool) void {
        _ = sdl.SDL_SetWindowBordered(self.handle, val);
    }

    pub fn setRelativeMouseMode(self: *Window, val: bool) void {
        _ = sdl.SDL_SetWindowRelativeMouseMode(self.handle, val);
        self.relativeMouse = val;
    }

    pub fn setFullscreenExclusive(self: *Window, val: bool) void {
        const displayID = sdl.SDL_GetDisplayForWindow(self.handle);
        var closestMode: sdl.SDL_DisplayMode = undefined;

        const fullscreenMode = sdl.SDL_GetDesktopDisplayMode(displayID);
        if (fullscreenMode == null) {
            std.log.err("Failed to get display mode: {s}", .{sdl.SDL_GetError()});
            return;
        }
        _ = sdl.SDL_GetClosestFullscreenDisplayMode(displayID, fullscreenMode.*.w, fullscreenMode.*.h, 0.0, true, &closestMode);
        _ = sdl.SDL_SetWindowFullscreenMode(self.handle, &closestMode);
        _ = sdl.SDL_SetWindowFullscreen(self.handle, val);
    }

    pub fn setFullscreenBorderless(self: *Window, val: bool) void {
        _ = sdl.SDL_SetWindowFullscreenMode(self.handle, null);
        _ = sdl.SDL_SetWindowFullscreen(self.handle, val);
    }

    pub fn isFullscreen(self: *const Window) bool {
        const flags = sdl.SDL_GetWindowFlags(self.handle);
        return (flags & sdl.SDL_WINDOW_FULLSCREEN) != 0;
    }

    pub fn getPixelExtent(self: *const Window) vk.VkExtent2D {
        var newExtent: vk.VkExtent2D = undefined;
        _ = sdl.SDL_GetWindowSizeInPixels(self.handle, @ptrCast(&newExtent.width), @ptrCast(&newExtent.height));
        return newExtent;
    }

    pub fn getExtent(self: *const Window) vk.VkExtent2D {
        var newExtent: vk.VkExtent2D = undefined;
        _ = sdl.SDL_GetWindowSize(self.handle, @ptrCast(&newExtent.width), @ptrCast(&newExtent.height));
        return newExtent;
    }
};
