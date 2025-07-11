const c = @import("../c.zig");
const check = @import("error.zig").check;

pub const VkAllocator = struct {
    handle: c.VmaAllocator,

    pub fn init(instance: c.VkInstance, gpi: c.VkDevice, gpu: c.VkPhysicalDevice) !VkAllocator {
        const vulkanFunctions = c.VmaVulkanFunctions{
            .vkGetInstanceProcAddr = c.vkGetInstanceProcAddr,
            .vkGetDeviceProcAddr = c.vkGetDeviceProcAddr,
        };

        const createInfo = c.VmaAllocatorCreateInfo{
            .physicalDevice = gpu,
            .device = gpi,
            .instance = instance,
            .flags = c.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
            // Passing the function pointers to VMA:
            .pVulkanFunctions = &vulkanFunctions,
        };

        var allocator: c.VmaAllocator = undefined;
        try check(c.vmaCreateAllocator(&createInfo, &allocator), "Failed to create VMA allocator");

        return VkAllocator{ .handle = allocator };
    }

    pub fn deinit(self: *VkAllocator) void {
        c.vmaDestroyAllocator(self.handle);
    }
};
