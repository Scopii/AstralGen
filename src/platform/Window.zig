const std = @import("std");
const c = @import("../c.zig");
const Swapchain = @import("../vulkan/SwapchainManager.zig").Swapchain;
const RenderPass = @import("../vulkan/ShaderPipeline.zig").RenderPass;

pub const Window = struct {
    pub const windowStatus = enum {
        active,
        inactive,
        needCreation,
        needUpdate,
        needDelete,
        needInactive,
        needActive,
    };
    handle: *c.SDL_Window,
    status: windowStatus = .needCreation,
    renderPass: RenderPass,
    extent: c.VkExtent2D,
    id: u32,

    pub fn init(id: u32, sdlWindow: *c.SDL_Window, renderPass: RenderPass, extent: c.VkExtent2D) !Window {
        return Window{ .handle = sdlWindow, .renderPass = renderPass, .extent = extent, .id = id };
    }
};
