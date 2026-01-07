const sdl = @import("../modules/sdl.zig").c;
const vk = @import("../modules/vk.zig").c;
const TexId = @import("../vulkan/resources/Texture.zig").Texture.TexId;

pub const Window = struct {
    pub const WindowState = enum { active, inactive, needCreation, needUpdate, needDelete, needInactive, needActive };
    handle: *sdl.SDL_Window,
    state: WindowState = .needCreation,
    renderTexId: TexId,
    extent: vk.VkExtent2D,
    id: WindowId,

    pub const WindowId = packed struct { val: u32 };

    pub fn init(id: u32, sdlWindow: *sdl.SDL_Window, renderTexId: TexId, extent: vk.VkExtent2D) !Window {
        return Window{ .handle = sdlWindow, .renderTexId = renderTexId, .extent = extent, .id = .{ .val = id } };
    }
};
