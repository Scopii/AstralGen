const vk = @import("../modules/vk.zig").c;
const check = @import("error.zig").check;

pub const VkAllocator = struct {
    handle: vk.VmaAllocator,

    pub fn init(instance: vk.VkInstance, gpi: vk.VkDevice, gpu: vk.VkPhysicalDevice) !VkAllocator {
        const vulkanFunctions = vk.VmaVulkanFunctions{
            .vkGetInstanceProcAddr = vk.vkGetInstanceProcAddr,
            .vkGetDeviceProcAddr = vk.vkGetDeviceProcAddr,
        };

        const createInf = vk.VmaAllocatorCreateInfo{
            .physicalDevice = gpu,
            .device = gpi,
            .instance = instance,
            .flags = vk.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
            .pVulkanFunctions = &vulkanFunctions, // Passing the Function Pointers
        };

        var vmaAlloc: vk.VmaAllocator = undefined;
        try check(vk.vmaCreateAllocator(&createInf, &vmaAlloc), "Failed to create VMA allocator");
        return VkAllocator{ .handle = vmaAlloc };
    }

    pub fn deinit(self: *VkAllocator) void {
        vk.vmaDestroyAllocator(self.handle);
    }
};
