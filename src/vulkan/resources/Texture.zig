const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const Context = @import("../Context.zig").Context;
const DescriptorManager = @import("DescriptorManager.zig").DescriptorManager;
const ResourceSlot = @import("Resource.zig").ResourceSlot;
const ResourceState = @import("../RenderGraph.zig").ResourceState;
const GpuAllocator = @import("GpuAllocator.zig").GpuAllocator;
const rc = @import("../../configs/renderConfig.zig");
const ve = @import("../Helpers.zig");
const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;


pub const Texture = struct {
    img: vk.VkImage,
    view: vk.VkImageView,
    allocation: vk.VmaAllocation,
    format: c_uint = rc.RENDER_IMG_FORMAT,
    imgType: ve.ImgType,
    extent: vk.VkExtent3D,
    bindlessIndex: u32,
    state: ResourceState = .{},

    pub fn getResourceSlot(self: *Texture) ResourceSlot {
        return ResourceSlot{ .index = self.bindlessIndex, .count = 1 };
    }
};
