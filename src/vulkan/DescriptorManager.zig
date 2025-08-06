const std = @import("std");
const c = @import("../c.zig");
const check = @import("error.zig").check;
const Context = @import("Context.zig").Context;
const ResourceManager = @import("ResourceManager.zig").ResourceManager;

pub const DescriptorManager = struct {
    alloc: std.mem.Allocator,
    gpi: c.VkDevice,
    descBufferAllocation: c.VmaAllocation,
    descBuffer: c.VkBuffer,
    descBufferAddr: c.VkDeviceAddress,
    computeLayout: c.VkDescriptorSetLayout,
    storageImageDescSize: u32,
    bufferSize: c.VkDeviceSize, // Store actual buffer size for validation

    pub fn init(alloc: std.mem.Allocator, context: *const Context, resourceMan: *const ResourceManager) !DescriptorManager {
        const gpi = context.gpi;

        // Query descriptor buffer properties
        var descBufferProps = c.VkPhysicalDeviceDescriptorBufferPropertiesEXT{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_PROPERTIES_EXT,
        };
        var physDevProps = c.VkPhysicalDeviceProperties2{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,
            .pNext = &descBufferProps,
        };
        c.vkGetPhysicalDeviceProperties2(context.gpu, &physDevProps);
        const storageImageDescSize: u32 = @intCast(descBufferProps.storageImageDescriptorSize);

        // Create descriptor set layout for compute pipeline
        const computeLayout = try createComputeDescriptorSetLayout(gpi);
        errdefer c.vkDestroyDescriptorSetLayout(gpi, computeLayout, null);

        // Get the exact size required for this layout from the driver
        var layoutSize: c.VkDeviceSize = undefined;
        c.pfn_vkGetDescriptorSetLayoutSizeEXT.?(gpi, computeLayout, &layoutSize);

        // Create descriptor buffer with driver-provided size
        const bufferInf = c.VkBufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = layoutSize,
            .usage = c.VK_BUFFER_USAGE_RESOURCE_DESCRIPTOR_BUFFER_BIT_EXT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        };

        const allocInf = c.VmaAllocationCreateInfo{
            .usage = c.VMA_MEMORY_USAGE_CPU_TO_GPU,
            .flags = c.VMA_ALLOCATION_CREATE_MAPPED_BIT,
        };

        var buffer: c.VkBuffer = undefined;
        var allocation: c.VmaAllocation = undefined;
        try check(c.vmaCreateBuffer(resourceMan.vkAlloc.handle, &bufferInf, &allocInf, &buffer, &allocation, null), "Failed to create descriptor buffer");

        // Get buffer device address
        const addrInf = c.VkBufferDeviceAddressInfo{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
            .buffer = buffer,
        };
        const bufferAddr = c.vkGetBufferDeviceAddress(gpi, &addrInf);

        return .{
            .alloc = alloc,
            .gpi = gpi,
            .descBuffer = buffer,
            .descBufferAllocation = allocation,
            .descBufferAddr = bufferAddr,
            .computeLayout = computeLayout,
            .storageImageDescSize = storageImageDescSize,
            .bufferSize = layoutSize,
        };
    }

    fn createComputeDescriptorSetLayout(gpi: c.VkDevice) !c.VkDescriptorSetLayout {
        const binding = c.VkDescriptorSetLayoutBinding{
            .binding = 0,
            .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
            .descriptorCount = 1,
            .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT,
            .pImmutableSamplers = null,
        };
        const layoutInf = c.VkDescriptorSetLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = 1,
            .pBindings = &binding,
            .flags = c.VK_DESCRIPTOR_SET_LAYOUT_CREATE_DESCRIPTOR_BUFFER_BIT_EXT, // Required for descriptor buffers
        };
        var computeLayout: c.VkDescriptorSetLayout = undefined;
        try check(c.vkCreateDescriptorSetLayout(gpi, &layoutInf, null, &computeLayout), "Failed to create descriptor set layout");
        return computeLayout;
    }

    pub fn updateStorageImageDescriptor(self: *DescriptorManager, vkAlloc: c.VmaAllocator, imageView: c.VkImageView, index: u32) !void {
        const gpi = self.gpi;

        // Validate offset bounds
        const requiredSize = index * self.storageImageDescSize + self.storageImageDescSize;
        if (requiredSize > self.bufferSize) {
            return error.DescriptorOffsetOutOfBounds;
        }

        const imageInf = c.VkDescriptorImageInfo{
            .sampler = null,
            .imageView = imageView,
            .imageLayout = c.VK_IMAGE_LAYOUT_GENERAL,
        };

        const getInf = c.VkDescriptorGetInfoEXT{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_GET_INFO_EXT,
            .pNext = null,
            .type = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
            .data = .{ .pStorageImage = &imageInf },
        };

        var descData: [32]u8 = undefined;
        if (self.storageImageDescSize > descData.len) {
            return error.DescriptorSizeTooLarge;
        }
        c.pfn_vkGetDescriptorEXT.?(gpi, &getInf, self.storageImageDescSize, &descData);

        var allocVmaInf: c.VmaAllocationInfo = undefined;
        c.vmaGetAllocationInfo(vkAlloc, self.descBufferAllocation, &allocVmaInf);

        const offset = index * self.storageImageDescSize;
        const mappedData = @as([*]u8, @ptrCast(allocVmaInf.pMappedData));
        const destPtr = mappedData + offset;

        @memcpy(destPtr[0..self.storageImageDescSize], descData[0..self.storageImageDescSize]);
    }

    pub fn deinit(self: *DescriptorManager, vkAlloc: c.VmaAllocator) void {
        c.vmaDestroyBuffer(vkAlloc, self.descBuffer, self.descBufferAllocation);
        c.vkDestroyDescriptorSetLayout(self.gpi, self.computeLayout, null);
    }
};
