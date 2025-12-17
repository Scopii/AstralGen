const sdl = @import("../modules/sdl.zig").c;
const vk = @import("../modules/vk.zig").c;

pub const Window = struct {
    pub const WindowState = enum { active, inactive, needCreation, needUpdate, needDelete, needInactive, needActive };
    handle: *sdl.SDL_Window,
    state: WindowState = .needCreation,
    renderId: u8,
    extent: vk.VkExtent2D,
    windowId: u32,

    pub fn init(windowId: u32, sdlWindow: *sdl.SDL_Window, renderId: u8, extent: vk.VkExtent2D) !Window {
        return Window{ .handle = sdlWindow, .renderId = renderId, .extent = extent, .windowId = windowId };
    }
};
