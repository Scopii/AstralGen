const std = @import("std");
const c = @import("../../c.zig");
const Allocator = std.mem.Allocator;
const ResourceManager = @import("ResourceManager.zig").ResourceManager;
const RenderImage = @import("ResourceManager.zig").RenderImage;

pub const RenderSequence = struct {
    renderImage: RenderImage,
    pub fn init(resourceMan: *const ResourceManager, extent: c.VkExtent2D) !RenderSequence {
        const renderImage = try resourceMan.createRenderImage(extent);

        return .{
            .renderImage = renderImage,
        };
    }

    pub fn deinit(self: *RenderSequence, resourceMan: ResourceManager) void {
        resourceMan.destroyRenderImage(self.renderImage);
    }
};
