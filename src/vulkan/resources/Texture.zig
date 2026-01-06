const vk = @import("../../modules/vk.zig").c;
const ResourceSlot = @import("Resource.zig").ResourceSlot;
const ResourceState = @import("../RenderGraph.zig").ResourceState;
const rc = @import("../../configs/renderConfig.zig");
const ve = @import("../Helpers.zig");

pub const Texture = struct {
    img: vk.VkImage,
    view: vk.VkImageView,
    allocation: vk.VmaAllocation,
    format: c_uint = rc.RENDER_IMG_FORMAT,
    texType: ve.TextureType,
    extent: vk.VkExtent3D,
    bindlessIndex: u32 = 0,
    state: ResourceState = .{},

    pub fn getResourceSlot(self: *Texture) ResourceSlot {
        return ResourceSlot{ .index = self.bindlessIndex, .count = 1 };
    }

    pub const TexInf = struct {
        texId: u32,
        memUse: ve.MemUsage,
        extent: vk.VkExtent3D,
        format: c_uint = rc.RENDER_IMG_FORMAT,
        texType: ve.TextureType,
    };

    pub fn create(texId: u32, memUse: ve.MemUsage, texType: ve.TextureType, width: u32, height: u32, depth: u32, format: c_int) TexInf {
        return .{
            .texId = texId,
            .memUse = memUse,
            .texType = texType,
            .extent = .{ .width = width, .height = height, .depth = depth },
            .format = format,
        };
    }
};
