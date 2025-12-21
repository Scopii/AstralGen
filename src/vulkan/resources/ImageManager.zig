const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const GpuAllocator = @import("GpuAllocator.zig").GpuAllocator;
const rc = @import("../../configs/renderConfig.zig");
const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;

pub const GpuImage = struct {
    allocation: vk.VmaAllocation,
    img: vk.VkImage,
    view: vk.VkImageView,
    extent3d: vk.VkExtent3D,
    format: vk.VkFormat,
    curLayout: u32 = vk.VK_IMAGE_LAYOUT_UNDEFINED,
};

pub const ImageMap = CreateMapArray(GpuImage, rc.GPU_IMG_MAX, u32, rc.GPU_IMG_MAX, 0);

pub const ImageManager = struct {
    cpuAlloc: Allocator,
    gpuAlloc: GpuAllocator, //deinit() in ResourceManager

    gpuImages: ImageMap = .{},
};
