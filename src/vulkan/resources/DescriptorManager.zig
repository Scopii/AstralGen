const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const vkFn = @import("../../modules/vk.zig");
const Allocator = std.mem.Allocator;
const GpuAllocator = @import("GpuAllocator.zig").GpuAllocator;
const Resource = @import("ResourceManager.zig").Resource;
const check = @import("../ErrorHelpers.zig").check;
const rc = @import("../../configs/renderConfig.zig");

pub const PushConstants = extern struct {
    camPosAndFov: [4]f32,
    camDir: [4]f32,
    runtime: f32,
    dataCount: u32,
    passImgIndex: u32,
    objectBufIndex: u32 = 0,
    viewProj: [4][4]f32,
};

pub const DescriptorBuffer = struct {
    allocation: vk.VmaAllocation,
    allocInf: vk.VmaAllocationInfo,
    buffer: vk.VkBuffer,
    gpuAddress: u64,
};

pub const DescriptorManager = struct {
    cpuAlloc: Allocator,
    gpuAlloc: GpuAllocator, // deinit() in ResourceManager
    gpi: vk.VkDevice,
    gpu: vk.VkPhysicalDevice,

    descBufferProps: vk.VkPhysicalDeviceDescriptorBufferPropertiesEXT,
    descLayout: vk.VkDescriptorSetLayout,
    descBuffer: DescriptorBuffer,
    pipeLayout: vk.VkPipelineLayout,

    pub fn init(cpuAlloc: Allocator, gpuAlloc: GpuAllocator, gpi: vk.VkDevice, gpu: vk.VkPhysicalDevice) !DescriptorManager {
        // Create Descriptor Layouts
        var bindings: [rc.bindingRegistry.len]vk.VkDescriptorSetLayoutBinding = undefined;
        for (0..bindings.len) |i| {
            switch (rc.bindingRegistry[i]) {
                .imageArrayBinding => |imgArray| {
                    bindings[i] = createDescriptorLayoutBinding(imgArray.binding, vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, imgArray.arrayLength, vk.VK_SHADER_STAGE_ALL);
                },
                .bufferBinding => |buffer| {
                    bindings[i] = createDescriptorLayoutBinding(buffer.binding, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, buffer.arrayLength, vk.VK_SHADER_STAGE_ALL);
                },
            }
        }
        const descLayout = try createDescriptorLayout(gpi, &bindings);
        errdefer vk.vkDestroyDescriptorSetLayout(gpi, descLayout, null);
        // Get exact size for this layout from the driver
        var layoutSize: vk.VkDeviceSize = undefined;
        vkFn.vkGetDescriptorSetLayoutSizeEXT.?(gpi, descLayout, &layoutSize);

        return .{
            .cpuAlloc = cpuAlloc,
            .gpuAlloc = gpuAlloc,
            .gpi = gpi,
            .gpu = gpu,
            .descBufferProps = getDescriptorBufferProperties(gpu),
            .descLayout = descLayout,
            .descBuffer = try gpuAlloc.allocDescriptorBuffer(layoutSize),
            .pipeLayout = try createPipelineLayout(gpi, descLayout, vk.VK_SHADER_STAGE_ALL, @sizeOf(PushConstants)),
        };
    }

    pub fn deinit(self: *DescriptorManager) void {
        self.gpuAlloc.freeGpuBuffer(self.descBuffer.buffer, self.descBuffer.allocation);
        vk.vkDestroyDescriptorSetLayout(self.gpi, self.descLayout, null);
        vk.vkDestroyPipelineLayout(self.gpi, self.pipeLayout, null);
    }

    pub fn updateImageDescriptor(self: *DescriptorManager, gpuImgView: vk.VkImageView, binding: u8, arrayIndex: u32) !void {
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
        try self.updateDescriptor(&getInf, binding, arrayIndex, self.descBufferProps.storageImageDescriptorSize);
    }

    pub fn updateBufferDescriptor(self: *DescriptorManager, gpuBuffer: Resource.GpuBuffer, binding: u8, arrayIndex: u32) !void {
        const addressInf = vk.VkDescriptorAddressInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_ADDRESS_INFO_EXT,
            .address = gpuBuffer.gpuAddress,
            .range = gpuBuffer.allocInf.size,
            .format = vk.VK_FORMAT_UNDEFINED,
        };
        const getInf = vk.VkDescriptorGetInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_GET_INFO_EXT,
            .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .data = .{ .pStorageBuffer = &addressInf },
        };
        try self.updateDescriptor(&getInf, binding, arrayIndex, self.descBufferProps.storageBufferDescriptorSize);
    }

    pub fn updateDescriptor(self: *DescriptorManager, descGetInf: *const vk.VkDescriptorGetInfoEXT, binding: u32, arrayIndex: u32, descSize: usize) !void {
        // Get Descriptor Data
        var descData: [64]u8 = undefined; // safe buffer size
        if (descSize > descData.len) return error.DescriptorSizeTooLarge;
        vkFn.vkGetDescriptorEXT.?(self.gpi, descGetInf, descSize, &descData);

        var bindingOffset: vk.VkDeviceSize = 0;
        vkFn.vkGetDescriptorSetLayoutBindingOffsetEXT.?(self.gpi, self.descLayout, binding, &bindingOffset);

        const mappedData = @as([*]u8, @ptrCast(self.descBuffer.allocInf.pMappedData));
        const finalOffset = bindingOffset + (arrayIndex * descSize); // Base Offset of the Array + (Index * Size of one Element)
        const destPtr = mappedData + finalOffset;
        @memcpy(destPtr[0..descSize], descData[0..descSize]);
    }
};

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
    var bindingFlags: [rc.bindingRegistry.len]vk.VkDescriptorBindingFlags = undefined;

    for (0..layoutBindings.len) |i| {
        bindingFlags[i] = vk.VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT;
    }
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
