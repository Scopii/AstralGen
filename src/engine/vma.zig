const c = @import("../c.zig");
const check = @import("error.zig").check;

pub const VkAllocator = struct {
    handle: c.VmaAllocator,

    pub fn init(instance: c.VkInstance, device: c.VkDevice, physicalDevice: c.VkPhysicalDevice) !VkAllocator {
        const createInfo = c.VmaAllocatorCreateInfo{
            .physicalDevice = physicalDevice,
            .device = device,
            .instance = instance,
        };

        var allocator: c.VmaAllocator = undefined;
        try check(c.vmaCreateAllocator(&createInfo, &allocator), "Failed to create VMA allocator");

        return VkAllocator{ .handle = allocator };
    }

    pub fn deinit(self: *VkAllocator) void {
        c.vmaDestroyAllocator(self.handle);
    }
};
