const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const vkFn = @import("../../modules/vk.zig");
const Allocator = std.mem.Allocator;
const Context = @import("../Context.zig").Context;
const VkAllocator = @import("../vma.zig").VkAllocator;
const GpuBuffer = @import("BufferManager.zig").GpuBuffer;
const GpuImage = @import("ImageManager.zig").GpuImage;
const check = @import("../error.zig").check;
const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;
const Object = @import("../../ecs/EntityManager.zig").Object;

pub const PushConstants = extern struct {
    camPosAndFov: [4]f32,
    camDir: [4]f32,
    runtime: f32,
    dataCount: u32,
    renderImgIndex: u32,
    padding: u32 = 0,
    viewProj: [4][4]f32,
};

pub const DescriptorBuffer = struct {
    pub const deviceAddress = u64;
    allocation: vk.VmaAllocation,
    buffer: vk.VkBuffer,
    gpuAddress: deviceAddress,
    size: vk.VkDeviceSize,
    count: u32 = 0,
};

pub const DescriptorManager = struct {
    cpuAlloc: Allocator,
    gpuAlloc: VkAllocator,
    gpi: vk.VkDevice,
    gpu: vk.VkPhysicalDevice,

    descBufferProps: vk.VkPhysicalDeviceDescriptorBufferPropertiesEXT,
    descLayout: vk.VkDescriptorSetLayout,
    descBuffer: DescriptorBuffer,
    pipeLayout: vk.VkPipelineLayout,

    pub fn init(cpuAlloc: Allocator, gpuAlloc: VkAllocator, gpi: vk.VkDevice, gpu: vk.VkPhysicalDevice) !DescriptorManager {
        // Query descriptor buffer properties
        const descBufferProps = getDescriptorBufferProperties(gpu);
        // Create Descriptor Layout
        const textureBinding = createDescriptorLayoutBinding(0, vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1024, vk.VK_SHADER_STAGE_ALL);
        const objectBinding = createDescriptorLayoutBinding(1, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, vk.VK_SHADER_STAGE_ALL);
        const descLayout = try createDescriptorLayout(gpi, &.{ textureBinding, objectBinding });
        errdefer vk.vkDestroyDescriptorSetLayout(gpi, descLayout, null);

        // Get the exact size for this layout from the driver
        var layoutSize: vk.VkDeviceSize = undefined;
        vkFn.vkGetDescriptorSetLayoutSizeEXT.?(gpi, descLayout, &layoutSize);

        const descBuffer = try createDescriptorBuffer(gpuAlloc.handle, gpi, layoutSize);

        return .{
            .cpuAlloc = cpuAlloc,
            .gpuAlloc = gpuAlloc,
            .gpi = gpi,
            .gpu = gpu,
            .descBufferProps = descBufferProps,
            .descLayout = descLayout,
            .descBuffer = descBuffer,
            .pipeLayout = try createPipelineLayout(gpi, descLayout, vk.VK_SHADER_STAGE_ALL, @sizeOf(PushConstants)),
        };
    }

    pub fn updateImageDescriptor(self: *DescriptorManager, gpuImgView: vk.VkImageView, renderId: u8) !void {
        // Get the Base Offset for Binding 0 (The Image Array)
        var bindingBaseOffset: vk.VkDeviceSize = 0;
        vkFn.vkGetDescriptorSetLayoutBindingOffsetEXT.?(self.gpi, self.descLayout, 0, &bindingBaseOffset);

        const imgInf = vk.VkDescriptorImageInfo{
            .sampler = null,
            .imageView = gpuImgView,
            .imageLayout = vk.VK_IMAGE_LAYOUT_GENERAL,
        };

        const getInf = vk.VkDescriptorGetInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_GET_INFO_EXT,
            .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
            .data = .{ .pStorageImage = &imgInf },
        };

        // Get Descriptor Data
        var descData: [64]u8 = undefined; // safe buffer size
        const descriptorSize = self.descBufferProps.storageImageDescriptorSize;
        if (descriptorSize > descData.len) return error.DescriptorSizeTooLarge;
        vkFn.vkGetDescriptorEXT.?(self.gpi, &getInf, descriptorSize, &descData);

        // Base Offset of the Array + (Index * Size of one Element)
        const finalOffset = bindingBaseOffset + (renderId * descriptorSize);

        var allocVmaInf: vk.VmaAllocationInfo = undefined;
        vk.vmaGetAllocationInfo(self.gpuAlloc.handle, self.descBuffer.allocation, &allocVmaInf);

        const mappedData = @as([*]u8, @ptrCast(allocVmaInf.pMappedData));
        const destPtr = mappedData + finalOffset;

        @memcpy(destPtr[0..descriptorSize], descData[0..descriptorSize]);
    }

    pub fn updateObjectBufferDescriptor(self: *DescriptorManager, gpuBuffer: GpuBuffer, buffId: u8) !void {
        var bindingOffset: vk.VkDeviceSize = 0;
        vkFn.vkGetDescriptorSetLayoutBindingOffsetEXT.?(self.gpi, self.descLayout, 1, &bindingOffset);

        const addressInf = vk.VkDescriptorAddressInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_ADDRESS_INFO_EXT,
            .address = gpuBuffer.gpuAddress,
            .range = gpuBuffer.size,
            .format = vk.VK_FORMAT_UNDEFINED,
        };

        const getInf = vk.VkDescriptorGetInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_GET_INFO_EXT,
            .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .data = .{ .pStorageBuffer = &addressInf },
        };

        // Get Descriptor Data
        var descData: [64]u8 = undefined; // safe buffer size
        const descriptorSize = self.descBufferProps.storageBufferDescriptorSize;
        if (descriptorSize > descData.len) return error.DescriptorSizeTooLarge;
        vkFn.vkGetDescriptorEXT.?(self.gpi, &getInf, descriptorSize, &descData);

        // Base Offset of the Array + (Index * Size of one Element)
        const finalOffset = bindingOffset + (buffId * descriptorSize);

        var allocVmaInf: vk.VmaAllocationInfo = undefined;
        vk.vmaGetAllocationInfo(self.gpuAlloc.handle, self.descBuffer.allocation, &allocVmaInf);

        const mappedData = @as([*]u8, @ptrCast(allocVmaInf.pMappedData));
        const destPtr = mappedData + finalOffset;

        @memcpy(destPtr[0..descriptorSize], descData[0..descriptorSize]);
    }

    pub fn deinit(self: *DescriptorManager) void {
        vk.vmaDestroyBuffer(self.gpuAlloc.handle, self.descBuffer.buffer, self.descBuffer.allocation);
        vk.vkDestroyDescriptorSetLayout(self.gpi, self.descLayout, null);
        vk.vkDestroyPipelineLayout(self.gpi, self.pipeLayout, null);
    }
};

fn createDescriptorBuffer(vma: vk.VmaAllocator, gpi: vk.VkDevice, size: vk.VkDeviceSize) !DescriptorBuffer { // Needs Data?
    const bufferUsage = vk.VK_BUFFER_USAGE_RESOURCE_DESCRIPTOR_BUFFER_BIT_EXT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT;
    const memUsage = vk.VMA_MEMORY_USAGE_CPU_TO_GPU;
    const memFlags = vk.VMA_ALLOCATION_CREATE_MAPPED_BIT;
    return createBuffer(vma, gpi, size, bufferUsage, memUsage, memFlags);
}

// FUNCTION IS DOUBLE, HERE AND IN RESOURCE MANAGER
fn createBuffer(vma: vk.VmaAllocator, gpi: vk.VkDevice, size: vk.VkDeviceSize, bufferUsage: vk.VkBufferUsageFlags, memUsage: vk.VmaMemoryUsage, memFlags: vk.VmaAllocationCreateFlags) !DescriptorBuffer {
    const bufferInf = vk.VkBufferCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = bufferUsage,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
    };
    var buffer: vk.VkBuffer = undefined;
    var allocation: vk.VmaAllocation = undefined;
    var allocVmaInf: vk.VmaAllocationInfo = undefined;
    const allocInf = vk.VmaAllocationCreateInfo{ .usage = memUsage, .flags = memFlags };
    try check(vk.vmaCreateBuffer(vma, &bufferInf, &allocInf, &buffer, &allocation, &allocVmaInf), "Failed to create buffer reference buffer");

    const addressInf = vk.VkBufferDeviceAddressInfo{ .sType = vk.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO, .buffer = buffer };
    const deviceAddress = vk.vkGetBufferDeviceAddress(gpi, &addressInf);

    return .{
        .buffer = buffer,
        .allocation = allocation,
        .gpuAddress = deviceAddress,
        .size = size,
    };
}

fn createDescriptorLayoutBinding(binding: u32, descType: vk.VkDescriptorType, count: u32, stageFlags: vk.VkShaderStageFlags) vk.VkDescriptorSetLayoutBinding {
    return vk.VkDescriptorSetLayoutBinding{
        .binding = binding,
        .descriptorType = descType,
        .descriptorCount = count,
        .stageFlags = stageFlags,
        .pImmutableSamplers = null,
    };
}

fn getDescriptorBufferProperties(gpu: vk.VkPhysicalDevice) vk.VkPhysicalDeviceDescriptorBufferPropertiesEXT {
    var descBufferProps = vk.VkPhysicalDeviceDescriptorBufferPropertiesEXT{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_PROPERTIES_EXT };
    var physDevProps = vk.VkPhysicalDeviceProperties2{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &descBufferProps };
    vk.vkGetPhysicalDeviceProperties2(gpu, &physDevProps);
    return descBufferProps;
}

fn createDescriptorLayout(gpi: vk.VkDevice, layoutBindings: []const vk.VkDescriptorSetLayoutBinding) !vk.VkDescriptorSetLayout {
    // 1. Binding Flags
    // Binding 0 (Images): Needs PARTIALLY_BOUND because the array is 1024 but we only use a few.
    // Binding 1 (Buffer): Needs 0.
    const bindingFlags = [_]vk.VkDescriptorBindingFlags{ vk.VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT, 0 };

    const bindingFlagsInf = vk.VkDescriptorSetLayoutBindingFlagsCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
        .bindingCount = bindingFlags.len,
        .pBindingFlags = &bindingFlags,
    };
    const layoutInf = vk.VkDescriptorSetLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .pNext = &bindingFlagsInf,
        .bindingCount = @intCast(layoutBindings.len),
        .pBindings = layoutBindings.ptr,
        .flags = vk.VK_DESCRIPTOR_SET_LAYOUT_CREATE_DESCRIPTOR_BUFFER_BIT_EXT,
    };
    var layout: vk.VkDescriptorSetLayout = undefined;
    try check(vk.vkCreateDescriptorSetLayout(gpi, &layoutInf, null, &layout), "Failed to create descriptor set layout");
    return layout;
}

fn createPipelineLayout(gpi: vk.VkDevice, descLayout: vk.VkDescriptorSetLayout, stageFlags: vk.VkShaderStageFlags, size: u32) !vk.VkPipelineLayout {
    const pcRange = vk.VkPushConstantRange{ .stageFlags = stageFlags, .offset = 0, .size = size };
    const pipeLayoutInf = vk.VkPipelineLayoutCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = if (descLayout != null) 1 else 0,
        .pSetLayouts = if (descLayout != null) &descLayout else null,
        .pushConstantRangeCount = if (size > 0) 1 else 0,
        .pPushConstantRanges = if (size > 0) &pcRange else null,
    };
    var layout: vk.VkPipelineLayout = undefined;
    try check(vk.vkCreatePipelineLayout(gpi, &pipeLayoutInf, null, &layout), "Failed to create pipeline layout");
    return layout;
}
