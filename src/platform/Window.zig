const sdl = @import("../modules/sdl.zig").c;
const vk = @import("../modules/vk.zig").c;

pub const Window = struct {
    pub const WindowState = enum { active, inactive, needCreation, needUpdate, needDelete, needInactive, needActive };
    handle: *sdl.SDL_Window,
    state: WindowState = .needCreation,
    passImgId: u32,
    extent: vk.VkExtent2D,
    windowId: u32,

    pub fn init(windowId: u32, sdlWindow: *sdl.SDL_Window, passImgId: u32, extent: vk.VkExtent2D) !Window {
        return Window{ .handle = sdlWindow, .passImgId = passImgId, .extent = extent, .windowId = windowId };
    }
};
