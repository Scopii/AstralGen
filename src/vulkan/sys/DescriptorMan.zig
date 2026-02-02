const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;
const PushConstants = @import("../types/res/PushConstants.zig").PushConstants;
const Texture = @import("../types/res/Texture.zig").Texture;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../configs/renderConfig.zig");
const vhF = @import("../help/Functions.zig");
const vk = @import("../../modules/vk.zig").c;
const vkFn = @import("../../modules/vk.zig");
const vhE = @import("../help/Enums.zig");
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

    storageBufCount: u32 = 0,
    storageBufMap: CreateMapArray(u32, rc.MAX_IN_FLIGHT * rc.BUF_MAX, u32, rc.MAX_IN_FLIGHT * rc.BUF_MAX, 0) = .{},
    storageBufDescSize: u64,
    storageBufOffset: u64,

    storageImgCount: u32 = 0,
    storageImgMap: CreateMapArray(u32, rc.MAX_IN_FLIGHT * rc.STORAGE_TEX_MAX, u32, rc.MAX_IN_FLIGHT * rc.STORAGE_TEX_MAX, 0) = .{},
    storageImgDescSize: u64,
    storageImgOffset: u64,

    sampledImgCount: u32 = 0,
    sampledImgMap: CreateMapArray(u32, rc.MAX_IN_FLIGHT * rc.SAMPLED_TEX_MAX, u32, rc.MAX_IN_FLIGHT * rc.SAMPLED_TEX_MAX, 0) = .{},
    sampledImgDescSize: u64,
    sampledImgOffset: u64,

    pub fn init(vma: Vma, gpi: vk.VkDevice, gpu: vk.VkPhysicalDevice) !DescriptorMan {
        // Create Descriptor Layouts
        var bindings: [rc.bindingRegistry.len]vk.VkDescriptorSetLayoutBinding = undefined;
        for (0..bindings.len) |i| {
            const binding = rc.bindingRegistry[i];
            bindings[i] = createDescriptorLayoutBinding(binding.binding, binding.descType, binding.len * rc.MAX_IN_FLIGHT, vk.VK_SHADER_STAGE_ALL);
        }
        const descLayout = try createDescriptorLayout(gpi, &bindings);
        errdefer vk.vkDestroyDescriptorSetLayout(gpi, descLayout, null);

        const descProps = getDescriptorBufferProperties(gpu);
        if (descProps.storageBufferDescriptorSize != @sizeOf(u64) * 2) return error.StorageDescSizeDoesNotMatch; // For fast Function Validation

        return .{
            .gpi = gpi,
            .descLayout = descLayout,
            .descBuffer = try vma.allocDescriptorBuffer(descLayout),
            .storageBufDescSize = descProps.storageBufferDescriptorSize,
            .storageBufOffset = getDescriptorBindingOffset(gpi, descLayout, rc.STORAGE_BUF_BINDING),
            .storageImgDescSize = descProps.storageImageDescriptorSize,
            .storageImgOffset = getDescriptorBindingOffset(gpi, descLayout, rc.STORAGE_TEX_BINDING),
            .sampledImgDescSize = descProps.sampledImageDescriptorSize,
            .sampledImgOffset = getDescriptorBindingOffset(gpi, descLayout, rc.SAMPLED_TEX_BINDING),
        };
    }

    pub fn deinit(self: *DescriptorMan, vma: Vma) void {
        vma.freeBuffer(self.descBuffer.handle, self.descBuffer.allocation);
        vk.vkDestroyDescriptorSetLayout(self.gpi, self.descLayout, null);
    }

    pub fn getStorageTextureIndex(self: *DescriptorMan, texId: Texture.TexId) u32 {
        return self.storageImgMap.get(texId.val);
    }

    pub fn getSampledTextureIndex(self: *DescriptorMan, texId: Texture.TexId) u32 {
        return self.sampledImgMap.get(texId.val);
    }

    pub fn getStorageBufferIndex(self: *DescriptorMan, bufId: Buffer.BufId) u32 {
        return self.storageBufMap.get(bufId.val);
    }

    pub fn removeStorageTextureDescriptor(self: *DescriptorMan, texId: Texture.TexId) void {
        self.storageImgMap.removeAtKey(texId.val);
    }

    pub fn removeSampledTextureDescriptor(self: *DescriptorMan, texId: Texture.TexId) void {
        self.sampledImgMap.removeAtKey(texId.val);
    }

    pub fn removeStorageBufferDescriptor(self: *DescriptorMan, bufId: Buffer.BufId) void {
        self.storageBufMap.removeAtKey(bufId.val);
    }

     pub fn updateStorageTextureDescriptor(self: *DescriptorMan, view: vk.VkImageView) !u32 {
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
        try self.updateDescriptor(&getInf, self.storageImgOffset, rc.STORAGE_TEX_BINDING, self.storageImgDescSize);
        self.storageImgCount += 1;
        return self.storageImgCount - 1;
    }

    pub fn updateSampledTextureDescriptor(self: *DescriptorMan, view: vk.VkImageView) !u32 {
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
        try self.updateDescriptor(&getInf, self.sampledImgOffset, rc.SAMPLED_TEX_BINDING, self.sampledImgDescSize);
        self.sampledImgCount += 1;
        return self.sampledImgCount - 1;
    }

    pub fn updateStorageBufferDescriptorFast(self: *DescriptorMan, gpuAddress: u64, size: u64) u32 {
        const descIndex = self.storageBufCount;
        const finalOffset = self.storageBufOffset + (descIndex * self.storageBufDescSize);
        const mappedData = @as([*]u8, @ptrCast(self.descBuffer.mappedPtr));

        const destPtr = @as(*extern struct { address: u64, range: u64 }, @ptrCast(@alignCast(mappedData + finalOffset)));
        destPtr.* = .{ .address = gpuAddress, .range = size };

        self.storageBufCount += 1;
        return descIndex;
    }

    pub fn updateDescriptor(self: *DescriptorMan, descGetInf: *const vk.VkDescriptorGetInfoEXT, bindingOffset: u64, descIndex: u32, descSize: usize) !void {
        var descData: [64]u8 = undefined; // safe buffer size
        if (descSize > descData.len) return error.DescriptorSizeTooLarge;
        vkFn.vkGetDescriptorEXT.?(self.gpi, descGetInf, descSize, &descData); // Getting Desc Data

        const mappedData = @as([*]u8, @ptrCast(self.descBuffer.mappedPtr));
        const offset = bindingOffset + (descIndex * descSize); // Base Offset of the Array + (Index * Size of one Element)
        const destPtr = mappedData + offset;
        @memcpy(destPtr[0..descSize], descData[0..descSize]);
    }

    // pub fn updateStorageBufferDescriptor(self: *DescriptorMan, gpuAddress: u64, size: u64) !void {
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
    //     try self.updateDescriptor(&getInf, self.storageBufOffset, rc.STORAGE_BUF_BINDING, self.storageBufDescSize);
    // }
};

fn getDescriptorBindingOffset(gpi: vk.VkDevice, descLayout: vk.VkDescriptorSetLayout, bind: u32) vk.VkDeviceSize {
    var bindOffset: vk.VkDeviceSize = 0;
    vkFn.vkGetDescriptorSetLayoutBindingOffsetEXT.?(gpi, descLayout, bind, &bindOffset);
    return bindOffset;
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
