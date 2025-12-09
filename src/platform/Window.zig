const c = @import("../c.zig");

pub const Window = struct {
    pub const WindowStatus = enum {
        active,
        inactive,
        needCreation,
        needUpdate,
        needDelete,
        needInactive,
        needActive,
    };
    handle: *c.SDL_Window,
    status: WindowStatus = .needCreation,
    renderId: u8,
    extent: c.VkExtent2D,
    windowId: u32,

    pub fn init(windowId: u32, sdlWindow: *c.SDL_Window, renderId: u8, extent: c.VkExtent2D) !Window {
        return Window{ .handle = sdlWindow, .renderId = renderId, .extent = extent, .windowId = windowId };
    }
};
