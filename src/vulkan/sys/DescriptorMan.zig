const PushConstants = @import("../types/res/PushConstants.zig").PushConstants;
const rc = @import("../../configs/renderConfig.zig");
const vhF = @import("../help/Functions.zig");
const vk = @import("../../modules/vk.zig").c;
const vkFn = @import("../../modules/vk.zig");
const Allocator = std.mem.Allocator;
const Vma = @import("Vma.zig").Vma;
const std = @import("std");

pub const DescriptorBuffer = struct {
    allocation: vk.VmaAllocation,
    mappedPtr: ?*anyopaque,
    size: vk.VkDeviceSize,
    handle: vk.VkBuffer,
    gpuAddress: u64,
};

pub const DescriptorMan = struct {
    gpi: vk.VkDevice,
    descLayout: vk.VkDescriptorSetLayout,
    descBuffer: DescriptorBuffer,

    storageBufDescSize: u64,
    storageBufBindingOffset: u64,
    storageImgDescSize: u64,
    storageImgBindingOffset: u64,
    sampledImgDescSize: u64,
    sampledImgBindingOffset: u64,

    pub fn init(vma: Vma, gpi: vk.VkDevice, gpu: vk.VkPhysicalDevice) !DescriptorMan {
        // Create Descriptor Layouts
        var bindings: [rc.bindingRegistry.len]vk.VkDescriptorSetLayoutBinding = undefined;
        for (0..bindings.len) |i| {
            const binding = rc.bindingRegistry[i];
            bindings[i] = createDescriptorLayoutBinding(binding.binding, binding.descType, binding.len, vk.VK_SHADER_STAGE_ALL);
        }
        const descLayout = try createDescriptorLayout(gpi, &bindings);
        errdefer vk.vkDestroyDescriptorSetLayout(gpi, descLayout, null);

        var layoutSize: vk.VkDeviceSize = undefined;
        vkFn.vkGetDescriptorSetLayoutSizeEXT.?(gpi, descLayout, &layoutSize);

        var storageBufBindingOffset: vk.VkDeviceSize = 0;
        var storageImgBindingOffset: vk.VkDeviceSize = 0;
        var sampledImgBindingOffset: vk.VkDeviceSize = 0;
        vkFn.vkGetDescriptorSetLayoutBindingOffsetEXT.?(gpi, descLayout, rc.STORAGE_BUF_BINDING, &storageBufBindingOffset);
        vkFn.vkGetDescriptorSetLayoutBindingOffsetEXT.?(gpi, descLayout, rc.STORAGE_TEX_BINDING, &storageImgBindingOffset);
        vkFn.vkGetDescriptorSetLayoutBindingOffsetEXT.?(gpi, descLayout, rc.SAMPLED_TEX_BINDING, &sampledImgBindingOffset);

        const descBufferProps = getDescriptorBufferProperties(gpu);
        if (descBufferProps.storageBufferDescriptorSize != @sizeOf(u64) * 2) return error.StorageDescSizeDoesntMatch; // For fast Function Validation

        return .{
            .gpi = gpi,
            .descLayout = descLayout,
            .descBuffer = try vma.allocDescriptorBuffer(layoutSize),
            .storageBufDescSize = descBufferProps.storageBufferDescriptorSize,
            .storageBufBindingOffset = storageBufBindingOffset,
            .storageImgDescSize = descBufferProps.storageImageDescriptorSize,
            .storageImgBindingOffset = storageImgBindingOffset,
            .sampledImgDescSize =  descBufferProps.sampledImageDescriptorSize,
            .sampledImgBindingOffset = sampledImgBindingOffset,
        };
    }

    pub fn deinit(self: *DescriptorMan, vma: Vma) void {
        vma.freeBuffer(self.descBuffer.handle, self.descBuffer.allocation);
        vk.vkDestroyDescriptorSetLayout(self.gpi, self.descLayout, null);
    }

    pub fn updateTextureDescriptor(self: *DescriptorMan, view: vk.VkImageView, arrayIndex: u32) !void {
        const imgInf = vk.VkDescriptorImageInfo{
            .sampler = null,
            .imageView = view,
            .imageLayout = vk.VK_IMAGE_LAYOUT_GENERAL,
        };
        const getInf = vk.VkDescriptorGetInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_GET_INFO_EXT,
            .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
            .data = .{ .pStorageImage = &imgInf },
        };
        try self.updateDescriptor(&getInf, self.storageImgBindingOffset, arrayIndex, self.storageImgDescSize);
    }

    pub fn updateSampledTextureDescriptor(self: *DescriptorMan, view: vk.VkImageView, arrayIndex: u32) !void {
        const imgInf = vk.VkDescriptorImageInfo{
            .sampler = null,
            .imageView = view,
            .imageLayout = vk.VK_IMAGE_LAYOUT_GENERAL,
        };
        const getInf = vk.VkDescriptorGetInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_GET_INFO_EXT,
            .type = vk.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
            .data = .{ .pSampledImage = &imgInf },
        };
        try self.updateDescriptor(&getInf, self.sampledImgBindingOffset, arrayIndex, self.sampledImgDescSize);
    }

    pub fn updateBufferDescriptorFast(self: *DescriptorMan, gpuAddress: u64, size: u64, arrayIndex: u32) void {
        const finalOffset = self.storageBufBindingOffset + (arrayIndex * self.storageBufDescSize);
        const mappedData = @as([*]u8, @ptrCast(self.descBuffer.mappedPtr));

        const destPtr = @as(*extern struct { address: u64, range: u64 }, @ptrCast(@alignCast(mappedData + finalOffset)));
        destPtr.* = .{ .address = gpuAddress, .range = size };
    }

    // pub fn updateBufferDescriptor(self: *DescriptorMan, gpuAddress: u64, size: u64, arrayIndex: u32) !void {
    //     const addressInf = vk.VkDescriptorAddressInfoEXT{
    //         .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_ADDRESS_INFO_EXT,
    //         .address = gpuAddress,
    //         .range = size,
    //         .format = vk.VK_FORMAT_UNDEFINED,
    //     };
    //     const getInf = vk.VkDescriptorGetInfoEXT{
    //         .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_GET_INFO_EXT,
    //         .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
    //         .data = .{ .pStorageBuffer = &addressInf },
    //     };
    //     try self.updateDescriptor(&getInf, self.storageBufBindingOffset, arrayIndex, self.storageBufDescSize);
    // }

    pub fn updateDescriptor(self: *DescriptorMan, descGetInf: *const vk.VkDescriptorGetInfoEXT, bindingOffset: u64, arrayIndex: u32, descSize: usize) !void {
        // Get Descriptor Data
        var descData: [64]u8 = undefined; // safe buffer size
        if (descSize > descData.len) return error.DescriptorSizeTooLarge;
        vkFn.vkGetDescriptorEXT.?(self.gpi, descGetInf, descSize, &descData);

        const mappedData = @as([*]u8, @ptrCast(self.descBuffer.mappedPtr));
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
    try vhF.check(vk.vkCreateDescriptorSetLayout(gpi, &layoutInf, null, &layout), "Failed to create descriptor set layout");
    return layout;
}