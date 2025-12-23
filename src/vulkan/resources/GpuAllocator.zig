const vk = @import("../../modules/vk.zig").c;
const std = @import("std");
const DescriptorBuffer = @import("DescriptorManager.zig").DescriptorBuffer;
const Resource = @import("ResourceManager.zig").Resource;
const rc = @import("../../configs/renderConfig.zig");
const check = @import("../ErrorHelpers.zig").check;

pub const GpuAllocator = struct {
    handle: vk.VmaAllocator,
    gpi: vk.VkDevice,

    pub fn init(instance: vk.VkInstance, gpi: vk.VkDevice, gpu: vk.VkPhysicalDevice) !GpuAllocator {
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
        try check(vk.vmaCreateAllocator(&createInf, &vmaAlloc), "Failed to create VMA/Gpu allocator");
        return .{ .handle = vmaAlloc, .gpi = gpi };
    }

    pub fn deinit(self: *const GpuAllocator) void {
        vk.vmaDestroyAllocator(self.handle);
    }

    pub fn allocDescriptorBuffer(self: *const GpuAllocator, size: vk.VkDeviceSize) !DescriptorBuffer {
        const buffUsage = vk.VK_BUFFER_USAGE_RESOURCE_DESCRIPTOR_BUFFER_BIT_EXT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT;
        const memUsage = vk.VMA_MEMORY_USAGE_CPU_TO_GPU;
        const memFlags = vk.VMA_ALLOCATION_CREATE_MAPPED_BIT;
        const gpuBuffer = try self.allocBuffer(size, buffUsage, memUsage, memFlags);
        return .{ .allocation = gpuBuffer.allocation, .allocInf = gpuBuffer.allocInf, .buffer = gpuBuffer.buffer, .gpuAddress = gpuBuffer.gpuAddress };
    }

    pub fn allocDefinedBuffer(self: *const GpuAllocator, bindingInf: rc.ResourceInfo.BufInf, memUsage: rc.ResourceInfo.MemUsage) !Resource.GpuBuffer {
        if (bindingInf.sizeOfElement == 0) {
            std.debug.print("Binding Info has invalid element size\n", .{});
            return error.AllocDefinedBufferFailed;
        }
        const bufferByteSize = @as(vk.VkDeviceSize, bindingInf.length) * bindingInf.sizeOfElement;

        var bufferBits: vk.VkBufferUsageFlags = switch (bindingInf.bufUsage) {
            .Storage => vk.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
            .Uniform => vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            .Index => vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
            .Vertex => vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            .Staging => vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        };

        if (bindingInf.bufUsage != .Staging) {
            bufferBits |= vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT;
            bufferBits |= vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT;
        }

        const memType: vk.VmaMemoryUsage = switch (memUsage) {
            .GpuOptimal => vk.VMA_MEMORY_USAGE_GPU_ONLY,
            .CpuWriteOptimal => vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
            .CpuReadOptimal => vk.VMA_MEMORY_USAGE_GPU_TO_CPU,
        };

        var memFlags: vk.VmaAllocationCreateFlags = switch (memUsage) {
            .GpuOptimal => 0,
            .CpuWriteOptimal, .CpuReadOptimal => vk.VMA_ALLOCATION_CREATE_MAPPED_BIT,
        };
        if (bindingInf.bufUsage == .Staging) memFlags |= vk.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT;

        return try self.allocBuffer(bufferByteSize, bufferBits, memType, memFlags);
    }

    pub fn allocBuffer(self: *const GpuAllocator, size: vk.VkDeviceSize, bufUsage: vk.VkBufferUsageFlags, memUsage: vk.VmaMemoryUsage, memFlags: vk.VmaAllocationCreateFlags) !Resource.GpuBuffer {
        const bufferInf = vk.VkBufferCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = bufUsage,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        };
        var buffer: vk.VkBuffer = undefined;
        var allocation: vk.VmaAllocation = undefined;
        var allocVmaInf: vk.VmaAllocationInfo = undefined;
        const allocCreateInf = vk.VmaAllocationCreateInfo{ .usage = memUsage, .flags = memFlags };
        try check(vk.vmaCreateBuffer(self.handle, &bufferInf, &allocCreateInf, &buffer, &allocation, &allocVmaInf), "Failed to create Gpu Buffer");

        const addressInf = vk.VkBufferDeviceAddressInfo{ .sType = vk.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO, .buffer = buffer };

        return .{
            .buffer = buffer,
            .allocation = allocation,
            .allocInf = allocVmaInf,
            .gpuAddress = vk.vkGetBufferDeviceAddress(self.gpi, &addressInf),
        };
    }

    pub fn allocGpuImage(self: *GpuAllocator, extent: vk.VkExtent3D, format: vk.VkFormat, memUsage: rc.ResourceInfo.MemUsage, arrayIndex: u32) !Resource.GpuImage {
        const mappedMemUsage: vk.VmaMemoryUsage = switch (memUsage) {
            .GpuOptimal => vk.VMA_MEMORY_USAGE_GPU_ONLY,
            .CpuWriteOptimal => vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
            .CpuReadOptimal => vk.VMA_MEMORY_USAGE_GPU_TO_CPU,
        };
        // Extending Flags as Parameters later!
        const drawImgUsages = vk.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
            vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT |
            vk.VK_IMAGE_USAGE_STORAGE_BIT |
            vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

        // Allocation from GPU local memory
        var img: vk.VkImage = undefined;
        var allocation: vk.VmaAllocation = undefined;
        const imgInf = createAllocatedImageInf(format, drawImgUsages, extent);
        const imgAllocInf = vk.VmaAllocationCreateInfo{ .usage = mappedMemUsage, .requiredFlags = vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT };
        try check(vk.vmaCreateImage(self.handle, &imgInf, &imgAllocInf, &img, &allocation, null), "Could not create Render Image");

        var view: vk.VkImageView = undefined;
        const viewInf = createAllocatedImageViewInf(format, img, vk.VK_IMAGE_ASPECT_COLOR_BIT);
        try check(vk.vkCreateImageView(self.gpi, &viewInf, null, &view), "Could not create Render Image View");

        return .{ .arrayIndex = arrayIndex, .allocation = allocation, .img = img, .view = view, .extent3d = extent, .format = format };
    }

    pub fn getAllocationInfo(self: *const GpuAllocator, allocation: vk.VmaAllocation) vk.VmaAllocationInfo {
        var allocVmaInf: vk.VmaAllocationInfo = undefined;
        vk.vmaGetAllocationInfo(self.handle, allocation, &allocVmaInf);
        return allocVmaInf;
    }

    pub fn freeGpuBuffer(self: *const GpuAllocator, buffer: vk.VkBuffer, allocation: vk.VmaAllocation) void {
        vk.vmaDestroyBuffer(self.handle, buffer, allocation);
    }

    pub fn freeGpuImage(self: *const GpuAllocator, gpuImg: Resource.GpuImage) void {
        vk.vkDestroyImageView(self.gpi, gpuImg.view, null);
        vk.vmaDestroyImage(self.handle, gpuImg.img, gpuImg.allocation);
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
