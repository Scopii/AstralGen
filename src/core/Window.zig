const std = @import("std");
const c = @import("../c.zig");
const PipelineType = @import("../engine/render/PipelineBucket.zig").PipelineType;
const Swapchain = @import("../engine/render/SwapchainManager.zig").Swapchain;

pub const windowStatus = enum {
    active,
    inactive,
};

pub const Window = struct {
    handle: *c.SDL_Window,
    status: windowStatus = .inactive,
    id: u32,
    swapchain: ?Swapchain = null,

    pub fn init(id: u32, sdlWindow: *c.SDL_Window) !Window {
        return Window{
            .handle = sdlWindow,
            .id = id,
        };
    }

    pub fn deinit(self: *Window) void {
        c.SDL_DestroyWindow(self.handle);
    }
};
