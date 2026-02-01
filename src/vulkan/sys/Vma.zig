const DescriptorBuffer = @import("DescriptorMan.zig").DescriptorBuffer;
const Texture = @import("../types/res/Texture.zig").Texture;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../configs/renderConfig.zig");
const vhF = @import("../help/Functions.zig");
const vk = @import("../../modules/vk.zig").c;
const vhE = @import("../help/Enums.zig");
const std = @import("std");

pub const Vma = struct {
    handle: vk.VmaAllocator,
    gpi: vk.VkDevice,
    gpu: vk.VkPhysicalDevice,

    pub fn init(instance: vk.VkInstance, gpi: vk.VkDevice, gpu: vk.VkPhysicalDevice) !Vma {
        const vulkanFunctions = vk.VmaVulkanFunctions{
            .vkGetInstanceProcAddr = vk.vkGetInstanceProcAddr,
            .vkGetDeviceProcAddr = vk.vkGetDeviceProcAddr,
        };
        const createInf = vk.VmaAllocatorCreateInfo{
            .physicalDevice = gpu,
            .device = gpi,
            .instance = instance,
            .flags = vk.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
            .pVulkanFunctions = &vulkanFunctions, // Passing Function Pointers
        };
        var vmaAlloc: vk.VmaAllocator = undefined;
        try vhF.check(vk.vmaCreateAllocator(&createInf, &vmaAlloc), "Failed to create VMA/Gpu allocator");

        return .{
            .handle = vmaAlloc,
            .gpi = gpi,
            .gpu = gpu,
        };
    }

    pub fn deinit(self: *const Vma) void {
        vk.vmaDestroyAllocator(self.handle);
    }

    pub fn allocDescriptorBuffer(self: *const Vma, size: vk.VkDeviceSize) !DescriptorBuffer {
        const bufUsage = vk.VK_BUFFER_USAGE_RESOURCE_DESCRIPTOR_BUFFER_BIT_EXT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT;
        const buffer = try self.allocBuffer(size, bufUsage, vk.VMA_MEMORY_USAGE_CPU_TO_GPU, vk.VMA_ALLOCATION_CREATE_MAPPED_BIT);
        return .{ .allocation = buffer.allocation, .mappedPtr = buffer.mappedPtr, .size = size, .handle = buffer.handle, .gpuAddress = buffer.gpuAddress };
    }

    pub fn allocStagingBuffer(self: *const Vma, size: vk.VkDeviceSize) !Buffer {
        const memFlags = vk.VMA_ALLOCATION_CREATE_MAPPED_BIT | vk.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT;
        return try self.allocBuffer(size, vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, vk.VMA_MEMORY_USAGE_CPU_ONLY, memFlags); // TEST CPU_TO_GPU and AUTO
    }

    pub fn printMemoryInfo(self: *const Vma, allocation: vk.VmaAllocation) void {
        var allocInf: vk.VmaAllocationInfo = undefined;
        vk.vmaGetAllocationInfo(self.handle, allocation, &allocInf);
        var memProps: vk.VkPhysicalDeviceMemoryProperties = undefined;
        vk.vkGetPhysicalDeviceMemoryProperties(self.gpu, &memProps);

        const flags = memProps.memoryTypes[allocInf.memoryType].propertyFlags;
        const isVram = (flags & vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) != 0;
        const isCpuVisible = (flags & vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) != 0;
        std.debug.print("Allocation is in VRAM: {}, CPU Visible: {}\n", .{ isVram, isCpuVisible });
    }

    pub fn allocDefinedBuffer(self: *const Vma, bufInf: Buffer.BufInf, memUse: vhE.MemUsage) !Buffer {
        const dataSize = bufInf.elementSize;

        if (dataSize == 0) {
            std.debug.print("Binding Info has invalid element size\n", .{});
            return error.AllocDefinedBufferFailed;
        }
        const bufferByteSize = @as(vk.VkDeviceSize, bufInf.len) * dataSize;

        var bufferBits: vk.VkBufferUsageFlags = switch (bufInf.typ) {
            .Storage => vk.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
            .Uniform => vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            .Index => vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
            .Vertex => vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            .Staging => vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            .Indirect => vk.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT | vk.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        };

        if (bufInf.typ != .Staging) {
            bufferBits |= vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT;
            bufferBits |= vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT;
        }

        const memType: vk.VmaMemoryUsage = switch (memUse) {
            .Gpu => vk.VMA_MEMORY_USAGE_GPU_ONLY,
            .CpuWrite => vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
            .CpuRead => vk.VMA_MEMORY_USAGE_GPU_TO_CPU,
        };

        var memFlags: vk.VmaAllocationCreateFlags = switch (memUse) {
            .Gpu => 0,
            .CpuWrite, .CpuRead => vk.VMA_ALLOCATION_CREATE_MAPPED_BIT,
        };
        if (bufInf.typ == .Staging) memFlags |= vk.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT;

        var buffer = try self.allocBuffer(bufferByteSize, bufferBits, memType, memFlags);
        buffer.update = bufInf.update;
        buffer.typ = bufInf.typ;
        return buffer;
    }

    pub fn allocBuffer(self: *const Vma, size: vk.VkDeviceSize, bufUsage: vk.VkBufferUsageFlags, memUse: vk.VmaMemoryUsage, memFlags: vk.VmaAllocationCreateFlags) !Buffer {
        const bufInf = vk.VkBufferCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = bufUsage,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        };
        var buffer: vk.VkBuffer = undefined;
        var allocation: vk.VmaAllocation = undefined;
        var allocVmaInf: vk.VmaAllocationInfo = undefined;
        const allocCreateInf = vk.VmaAllocationCreateInfo{ .usage = memUse, .flags = memFlags };
        try vhF.check(vk.vmaCreateBuffer(self.handle, &bufInf, &allocCreateInf, &buffer, &allocation, &allocVmaInf), "Failed to create Gpu Buffer");

        var gpuAddress: u64 = 0;
        if ((bufUsage & vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT) != 0) {
            const addressInf = vk.VkBufferDeviceAddressInfo{ .sType = vk.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO, .buffer = buffer };
            gpuAddress = vk.vkGetBufferDeviceAddress(self.gpi, &addressInf);
        }

        return .{
            .handle = buffer,
            .allocation = allocation,
            .mappedPtr = allocVmaInf.pMappedData,
            .size = allocVmaInf.size,
            .gpuAddress = gpuAddress,
        };
    }

    pub fn allocTexture(self: *Vma, texInf: Texture.TexInf, memUse: vhE.MemUsage) !Texture {
        const memType: vk.VmaMemoryUsage = switch (memUse) {
            .Gpu => vk.VMA_MEMORY_USAGE_GPU_ONLY,
            .CpuWrite => vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
            .CpuRead => vk.VMA_MEMORY_USAGE_GPU_TO_CPU,
        };
        var use: vk.VkImageUsageFlags = vk.VK_IMAGE_USAGE_TRANSFER_SRC_BIT | vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT;

        switch (texInf.typ) {
            .Color => {
                use |= vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
                use |= vk.VK_IMAGE_USAGE_STORAGE_BIT; // Compute Write
            },
            .Depth, .Stencil => use |= vk.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT, // Depth usually CANNOT be Storage!
        }

        const format: c_uint = switch (texInf.typ) {
            .Color => rc.TEX_COLOR_FORMAT,
            .Depth, .Stencil => rc.TEX_DEPTH_FORMAT,
        };

        // Allocation from GPU local memory
        var img: vk.VkImage = undefined;
        var allocation: vk.VmaAllocation = undefined;
        const extent = vk.VkExtent3D{ .width = texInf.width, .height = texInf.height, .depth = texInf.depth };

        const imgInf = createAllocatedImageInf(format, use, extent);
        const imgAllocInf = vk.VmaAllocationCreateInfo{ .usage = memType, .requiredFlags = vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT };
        try vhF.check(vk.vmaCreateImage(self.handle, &imgInf, &imgAllocInf, &img, &allocation, null), "Could not create Render Image");

        const aspectMask: vk.VkImageAspectFlags = switch (texInf.typ) {
            .Color => vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .Depth => vk.VK_IMAGE_ASPECT_DEPTH_BIT,
            .Stencil => vk.VK_IMAGE_ASPECT_STENCIL_BIT,
        };
        var view: vk.VkImageView = undefined;
        const viewInf = createAllocatedImageViewInf(format, img, aspectMask);
        try vhF.check(vk.vkCreateImageView(self.gpi, &viewInf, null, &view), "Could not create Render Image View");

        return .{
            .allocation = allocation,
            .base = .{ .extent = extent, .format = format, .texType = texInf.typ, .img = img, .view = view },
        };
    }

    pub fn getAllocationInfo(self: *const Vma, allocation: vk.VmaAllocation) vk.VmaAllocationInfo {
        var allocVmaInf: vk.VmaAllocationInfo = undefined;
        vk.vmaGetAllocationInfo(self.handle, allocation, &allocVmaInf);
        return allocVmaInf;
    }

    pub fn freeBuffer(self: *const Vma, buffer: vk.VkBuffer, allocation: vk.VmaAllocation) void {
        vk.vmaDestroyBuffer(self.handle, buffer, allocation);
    }

    pub fn freeTexture(self: *const Vma, tex: *Texture) void {
        vk.vkDestroyImageView(self.gpi, tex.base.view, null);
        vk.vmaDestroyImage(self.handle, tex.base.img, tex.allocation);
    }
};

fn createAllocatedImageInf(format: vk.VkFormat, usageFlags: vk.VkImageUsageFlags, extent3d: vk.VkExtent3D) vk.VkImageCreateInfo {
    return vk.VkImageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = vk.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = extent3d,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = vk.VK_SAMPLE_COUNT_1_BIT, // MSAA not used by default!
        .tiling = vk.VK_IMAGE_TILING_OPTIMAL, // Optimal GPU Format has to be changed to LINEAR for CPU Read
        .usage = usageFlags,
    };
}

fn createAllocatedImageViewInf(format: vk.VkFormat, img: vk.VkImage, aspectFlags: vk.VkImageAspectFlags) vk.VkImageViewCreateInfo {
    return vk.VkImageViewCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
        .image = img,
        .format = format,
        .subresourceRange = vk.VkImageSubresourceRange{
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
            .aspectMask = aspectFlags,
        },
    };
}
