const std = @import("std");
const c = @import("../../c.zig");
const check = @import("../error.zig").check;
const VkAllocator = @import("../vma.zig").VkAllocator;

pub const AllocatedImage = struct {
    allocation: c.VmaAllocation,
    image: c.VkImage,
    view: c.VkImageView,
    extent3d: c.VkExtent3D,
    format: c.VkFormat,
};
