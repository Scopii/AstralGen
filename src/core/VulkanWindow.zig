const std = @import("std");
const c = @import("../c.zig");
const PipelineType = @import("../engine/render/PipelineBucket.zig").PipelineType;

pub const VulkanWindow = struct {
    pub const windowStatus = enum {
        active,
        passive,
        inactive,
    };
    handle: *c.SDL_Window,
    extent: c.VkExtent2D,
    pipeType: PipelineType,
    status: windowStatus = .active,
    id: u32,

    pub fn init(width: c_int, height: c_int, id: u32, sdlWindow: *c.SDL_Window, pipeType: PipelineType) !VulkanWindow {
        return VulkanWindow{
            .handle = sdlWindow,
            .extent = c.VkExtent2D{ .width = @intCast(width), .height = @intCast(height) },
            .pipeType = pipeType,
            .id = id,
        };
    }

    pub fn deinit(self: *VulkanWindow) void {
        c.SDL_DestroyWindow(self.handle);
    }
};
