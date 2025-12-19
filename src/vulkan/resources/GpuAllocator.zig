const vk = @import("../../modules/vk.zig").c;
const DescriptorBuffer = @import("DescriptorManager.zig").DescriptorBuffer;
const GpuBuffer = @import("BufferManager.zig").GpuBuffer;
const GpuImage = @import("ImageManager.zig").GpuImage;

const check = @import("../error.zig").check;

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

    pub fn allocDescriptorBuffer(self: *const GpuAllocator, size: vk.VkDeviceSize) !DescriptorBuffer {
        const bufferUsage = vk.VK_BUFFER_USAGE_RESOURCE_DESCRIPTOR_BUFFER_BIT_EXT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT;
        const memUsage = vk.VMA_MEMORY_USAGE_CPU_TO_GPU;
        const memFlags = vk.VMA_ALLOCATION_CREATE_MAPPED_BIT;
        const gpuBuffer = try self.allocBuffer(size, null, bufferUsage, memUsage, memFlags);
        return .{ .allocation = gpuBuffer.allocation, .allocInf = gpuBuffer.allocInf, .buffer = gpuBuffer.buffer, .gpuAddress = gpuBuffer.gpuAddress };
    }

    pub fn allocDefinedBuffer(self: *const GpuAllocator, size: vk.VkDeviceSize, data: ?[]const u8, bufferType: enum { storage, uniform, testBuffer }) !GpuBuffer {
        const bufferUsage: u32 = switch (bufferType) {
            .storage, .testBuffer => vk.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT | vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
            .uniform => vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        };
        const memUsage: u32 = switch (bufferType) {
            .storage => vk.VMA_MEMORY_USAGE_GPU_ONLY,
            .uniform, .testBuffer => vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
        };
        const memFlags: u32 = switch (bufferType) {
            .uniform,
            => vk.VMA_ALLOCATION_CREATE_MAPPED_BIT,
            .testBuffer => vk.VMA_ALLOCATION_CREATE_MAPPED_BIT | vk.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
            .storage => 0, // Storage buffers should not be mapped!
        };
        return try self.allocBuffer(size, data, bufferUsage, memUsage, memFlags);
    }

    pub fn allocBuffer(self: *const GpuAllocator, size: vk.VkDeviceSize, data: ?[]const u8, bufferUsage: vk.VkBufferUsageFlags, memUsage: vk.VmaMemoryUsage, memFlags: vk.VmaAllocationCreateFlags) !GpuBuffer {
        const bufferInf = vk.VkBufferCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = bufferUsage,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        };
        var buffer: vk.VkBuffer = undefined;
        var allocation: vk.VmaAllocation = undefined;
        var allocVmaInf: vk.VmaAllocationInfo = undefined;
        const allocCreateInf = vk.VmaAllocationCreateInfo{ .usage = memUsage, .flags = memFlags };
        try check(vk.vmaCreateBuffer(self.handle, &bufferInf, &allocCreateInf, &buffer, &allocation, &allocVmaInf), "Failed to create Gpu Buffer");

        const addressInf = vk.VkBufferDeviceAddressInfo{ .sType = vk.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO, .buffer = buffer };
        // Init with data if given
        if (data) |initData| {
            const mappedPtr = @as([*]u8, @ptrCast(allocVmaInf.pMappedData));
            @memcpy(mappedPtr[0..initData.len], initData);
        }

        return .{
            .buffer = buffer,
            .allocation = allocation,
            .allocInf = allocVmaInf,
            .gpuAddress = vk.vkGetBufferDeviceAddress(self.gpi, &addressInf),
        };
    }

    pub fn allocGpuImage(self: *GpuAllocator, extent: vk.VkExtent3D, format: vk.VkFormat, usage: vk.VmaMemoryUsage) !GpuImage {
        // Extending Flags as Parameters later!
        const drawImgUsages = vk.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
            vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT |
            vk.VK_IMAGE_USAGE_STORAGE_BIT |
            vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

        // Allocation from GPU local memory
        var img: vk.VkImage = undefined;
        var allocation: vk.VmaAllocation = undefined;
        const imgInf = createAllocatedImageInf(format, drawImgUsages, extent);
        const imgAllocInf = vk.VmaAllocationCreateInfo{ .usage = usage, .requiredFlags = vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT };
        try check(vk.vmaCreateImage(self.handle, &imgInf, &imgAllocInf, &img, &allocation, null), "Could not create Render Image");

        var view: vk.VkImageView = undefined;
        const viewInf = createAllocatedImageViewInf(format, img, vk.VK_IMAGE_ASPECT_COLOR_BIT);
        try check(vk.vkCreateImageView(self.gpi, &viewInf, null, &view), "Could not create Render Image View");

        return .{
            .allocation = allocation,
            .img = img,
            .view = view,
            .extent3d = extent,
            .format = format,
        };
    }

    pub fn getAllocationInfo(self: *const GpuAllocator, allocation: vk.VmaAllocation) vk.VmaAllocationInfo {
        var allocVmaInf: vk.VmaAllocationInfo = undefined;
        vk.vmaGetAllocationInfo(self.handle, allocation, &allocVmaInf);
        return allocVmaInf;
    }

    pub fn freeGpuBuffer(self: *const GpuAllocator, buffer: vk.VkBuffer, allocation: vk.VmaAllocation) void {
        vk.vmaDestroyBuffer(self.handle, buffer, allocation);
    }

    pub fn freeGpuImage(self: *const GpuAllocator, gpuImg: GpuImage) void {
        vk.vkDestroyImageView(self.gpi, gpuImg.view, null);
        vk.vmaDestroyImage(self.handle, gpuImg.img, gpuImg.allocation);
    }

    pub fn deinit(self: *const GpuAllocator) void {
        vk.vmaDestroyAllocator(self.handle);
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

fn createAllocatedImageViewInf(format: vk.VkFormat, image: vk.VkImage, aspectFlags: vk.VkImageAspectFlags) vk.VkImageViewCreateInfo {
    return vk.VkImageViewCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
        .image = image,
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
