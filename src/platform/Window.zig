const std = @import("std");
const c = @import("../c.zig");
const PipelineType = @import("../vulkan/PipelineBucket.zig").PipelineType;
const Swapchain = @import("../vulkan/SwapchainManager.zig").Swapchain;

pub const windowStatus = enum {
    active,
    inactive,
    needCreation,
    needUpdate,
    needDelete,
};

pub const Window = struct {
    handle: *c.SDL_Window,
    status: windowStatus = .needCreation,
    pipeType: PipelineType,
    extent: c.VkExtent2D,
    id: u32,

    pub fn init(id: u32, sdlWindow: *c.SDL_Window, pipeType: PipelineType, extent: c.VkExtent2D) !Window {
        return Window{
            .handle = sdlWindow,
            .pipeType = pipeType,
            .extent = extent,
            .id = id,
        };
    }
};
