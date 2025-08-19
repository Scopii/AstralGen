const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const Context = @import("Context.zig").Context;
const VkAllocator = @import("vma.zig").VkAllocator;
const check = @import("error.zig").check;

pub const GpuImage = struct {
    allocation: c.VmaAllocation,
    image: c.VkImage,
    view: c.VkImageView,
    extent3d: c.VkExtent3D,
    format: c.VkFormat,
    curLayout: u32 = c.VK_IMAGE_LAYOUT_UNDEFINED,
};

pub const GpuBuffer = struct {
    pub const deviceAddress = u64;
    allocation: c.VmaAllocation,
    buffer: c.VkBuffer,
    gpuAddress: deviceAddress,
    size: c.VkDeviceSize,
};

pub const ResourceManager = struct {
    cpuAlloc: Allocator,
    gpuAlloc: VkAllocator,
    gpi: c.VkDevice,
    gpu: c.VkPhysicalDevice,

    layout: c.VkDescriptorSetLayout,
    imageDescBuffer: GpuBuffer,
    imageDescSize: u32,

    pub fn init(alloc: Allocator, context: *const Context) !ResourceManager {
        const gpi = context.gpi;
        const gpuAlloc = try VkAllocator.init(context.instance, context.gpi, context.gpu);

        // Query descriptor buffer properties
        var descBufferProps = c.VkPhysicalDeviceDescriptorBufferPropertiesEXT{ .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_PROPERTIES_EXT };
        var physDevProps = c.VkPhysicalDeviceProperties2{ .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &descBufferProps };
        c.vkGetPhysicalDeviceProperties2(context.gpu, &physDevProps);
        const imageDescSize: u32 = @intCast(descBufferProps.storageImageDescriptorSize); // Whole gpu memory?
        // Create descriptor set layout for compute pipeline
        const layout = try createDescriptorLayout(gpi, 0, c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1, c.VK_SHADER_STAGE_COMPUTE_BIT);
        errdefer c.vkDestroyDescriptorSetLayout(gpi, layout, null);
        // Get the exact size required for this layout from the driver
        var layoutSize: c.VkDeviceSize = undefined;
        c.pfn_vkGetDescriptorSetLayoutSizeEXT.?(gpi, layout, &layoutSize);

        // Create descriptor buffer with driver-provided size
        const imageDescBuffer = try createDefinedBuffer(gpuAlloc.handle, gpi, layoutSize, null, .descriptor);

        return .{
            .cpuAlloc = alloc,
            .gpuAlloc = gpuAlloc,
            .gpi = context.gpi,
            .gpu = context.gpu,
            .imageDescSize = imageDescSize,
            .imageDescBuffer = imageDescBuffer,
            .layout = layout,
        };
    }

    pub fn deinit(self: *ResourceManager) void {
        c.vmaDestroyBuffer(self.gpuAlloc.handle, self.imageDescBuffer.buffer, self.imageDescBuffer.allocation);
        c.vkDestroyDescriptorSetLayout(self.gpi, self.layout, null);
        self.gpuAlloc.deinit();
    }

    pub fn createGpuImage(self: *const ResourceManager, extent: c.VkExtent3D, format: c.VkFormat, usage: c.VmaMemoryUsage) !GpuImage {
        // Extending Flags as Parameters later
        const drawImageUsages = c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
            c.VK_IMAGE_USAGE_TRANSFER_DST_BIT |
            c.VK_IMAGE_USAGE_STORAGE_BIT |
            c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

        // Allocation from GPU local memory
        const imageInf = createAllocatedImageInf(format, drawImageUsages, extent);
        const imageAllocInf = c.VmaAllocationCreateInfo{ .usage = usage, .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT };

        var image: c.VkImage = undefined;
        var allocation: c.VmaAllocation = undefined;
        var view: c.VkImageView = undefined;
        try check(c.vmaCreateImage(self.gpuAlloc.handle, &imageInf, &imageAllocInf, &image, &allocation, null), "Could not create Render Image");
        const renderViewInf = createAllocatedImageViewInf(format, image, c.VK_IMAGE_ASPECT_COLOR_BIT);
        try check(c.vkCreateImageView(self.gpi, &renderViewInf, null, &view), "Could not create Render Image View");

        return .{
            .allocation = allocation,
            .image = image,
            .view = view,
            .extent3d = extent,
            .format = format,
        };
    }

    pub fn updateImageDescriptor(self: *ResourceManager, imageView: c.VkImageView, index: u32) !void {
        const gpi = self.gpi;
        const vkAlloc = self.gpuAlloc.handle;
        const imageDescSize = self.imageDescSize;

        const imageInf = c.VkDescriptorImageInfo{ .sampler = null, .imageView = imageView, .imageLayout = c.VK_IMAGE_LAYOUT_GENERAL };

        const getInf = c.VkDescriptorGetInfoEXT{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_GET_INFO_EXT,
            .type = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
            .data = .{ .pStorageImage = &imageInf },
        };

        var descData: [32]u8 = undefined;
        if (imageDescSize > descData.len) return error.DescriptorSizeTooLarge;
        c.pfn_vkGetDescriptorEXT.?(gpi, &getInf, imageDescSize, &descData);

        var allocVmaInf: c.VmaAllocationInfo = undefined;
        c.vmaGetAllocationInfo(vkAlloc, self.imageDescBuffer.allocation, &allocVmaInf);

        const offset = index * imageDescSize;
        const mappedData = @as([*]u8, @ptrCast(allocVmaInf.pMappedData));
        const destPtr = mappedData + offset;
        @memcpy(destPtr[0..imageDescSize], descData[0..imageDescSize]);
    }

    pub fn createTestDataBuffer(self: *const ResourceManager, extent: c.VkExtent3D) !GpuBuffer {
        const bufferSize = extent.width * extent.height * @sizeOf([4]f32);
        const vma = self.gpuAlloc.handle;

        const buffer = try createDefinedBuffer(vma, self.gpi, bufferSize, null, .testBuffer);
        // Initialize with test data - sine wave pattern
        var allocVmaInf: c.VmaAllocationInfo = undefined;
        c.vmaGetAllocationInfo(vma, buffer.allocation, &allocVmaInf);
        const dataPtr = @as([*][4]f32, @ptrCast(@alignCast(allocVmaInf.pMappedData)));

        for (0..extent.height) |y| {
            for (0..extent.width) |x| {
                const index = y * extent.width + x;
                const fx = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(extent.width));
                const fy = @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(extent.height));

                dataPtr[index] = [4]f32{
                    std.math.sin(fx * 6.28) * 0.5, // x offset
                    std.math.cos(fy * 6.28) * 0.5, // y offset
                    0.0, // z offset
                    std.math.sin(fx * fy * 12.56) * 0.3, // radius variation
                };
            }
        }
        return buffer;
    }

    pub fn updateGpuBuffer(self: *const ResourceManager, bufRef: GpuBuffer, data: []const u8, offset: c.VkDeviceSize) !void {
        if (offset + data.len > bufRef.size) return error.BufferOverflow;

        var allocVmaInf: c.VmaAllocationInfo = undefined;
        c.vmaGetAllocationInfo(self.gpuAlloc.handle, bufRef.allocation, &allocVmaInf);
        const mappedPtr = @as([*]u8, @ptrCast(allocVmaInf.pMappedData));
        @memcpy(mappedPtr[offset .. offset + data.len], data);
    }

    pub fn destroyGpuBuffer(self: *const ResourceManager, bufRef: GpuBuffer) void {
        c.vmaDestroyBuffer(self.gpuAlloc.handle, bufRef.buffer, bufRef.allocation);
    }

    pub fn destroyGpuImage(self: *const ResourceManager, image: GpuImage) void {
        c.vkDestroyImageView(self.gpi, image.view, null);
        c.vmaDestroyImage(self.gpuAlloc.handle, image.image, image.allocation);
    }
};

fn createDefinedBuffer(vma: c.VmaAllocator, gpi: c.VkDevice, size: c.VkDeviceSize, data: ?[]const u8, bufferType: enum { storage, uniform, descriptor, testBuffer }) !GpuBuffer {
    const bufferUsage: u32 = switch (bufferType) {
        .storage, .testBuffer => c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        .uniform => c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        .descriptor => c.VK_BUFFER_USAGE_RESOURCE_DESCRIPTOR_BUFFER_BIT_EXT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
    };
    const memoryUsage: u32 = switch (bufferType) {
        .storage => c.VMA_MEMORY_USAGE_GPU_ONLY,
        .uniform, .descriptor, .testBuffer => c.VMA_MEMORY_USAGE_CPU_TO_GPU,
    };
    const memoryFlags: u32 = switch (bufferType) {
        .uniform, .descriptor => c.VMA_ALLOCATION_CREATE_MAPPED_BIT,
        .testBuffer => c.VMA_ALLOCATION_CREATE_MAPPED_BIT | c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
        .storage => 0, // Storage buffers should not be mapped
    };
    return createBuffer(vma, gpi, size, data, bufferUsage, memoryUsage, memoryFlags);
}

fn createDescriptorLayout(gpi: c.VkDevice, binding: u32, descType: c.VkDescriptorType, count: u32, stageFlags: c.VkShaderStageFlags) !c.VkDescriptorSetLayout {
    const layoutBinding = c.VkDescriptorSetLayoutBinding{
        .binding = binding,
        .descriptorType = descType,
        .descriptorCount = count,
        .stageFlags = stageFlags,
        .pImmutableSamplers = null,
    };
    const layoutInf = c.VkDescriptorSetLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = count,
        .pBindings = &layoutBinding,
        .flags = c.VK_DESCRIPTOR_SET_LAYOUT_CREATE_DESCRIPTOR_BUFFER_BIT_EXT, // Required for descriptor buffers
    };
    var layout: c.VkDescriptorSetLayout = undefined;
    try check(c.vkCreateDescriptorSetLayout(gpi, &layoutInf, null, &layout), "Failed to create descriptor set layout");
    return layout;
}

fn createBuffer(vma: c.VmaAllocator, gpi: c.VkDevice, size: c.VkDeviceSize, data: ?[]const u8, bufferUsage: c.VkBufferUsageFlags, memUsage: c.VmaMemoryUsage, memFlags: c.VmaAllocationCreateFlags) !GpuBuffer {
    const bufferInf = c.VkBufferCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = bufferUsage,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
    };
    var buffer: c.VkBuffer = undefined;
    var allocation: c.VmaAllocation = undefined;
    var allocVmaInf: c.VmaAllocationInfo = undefined;
    const allocInf = c.VmaAllocationCreateInfo{ .usage = memUsage, .flags = memFlags };
    try check(c.vmaCreateBuffer(vma, &bufferInf, &allocInf, &buffer, &allocation, &allocVmaInf), "Failed to create buffer reference buffer");

    const addressInf = c.VkBufferDeviceAddressInfo{ .sType = c.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO, .buffer = buffer };
    const deviceAddress = c.vkGetBufferDeviceAddress(gpi, &addressInf);

    // Initialize with data if provided
    if (data) |initData| {
        const mappedPtr = @as([*]u8, @ptrCast(allocVmaInf.pMappedData));
        @memcpy(mappedPtr[0..initData.len], initData);
    }

    return GpuBuffer{
        .buffer = buffer,
        .allocation = allocation,
        .gpuAddress = deviceAddress,
        .size = size,
    };
}

fn createAllocatedImageInf(format: c.VkFormat, usageFlags: c.VkImageUsageFlags, extent3d: c.VkExtent3D) c.VkImageCreateInfo {
    return c.VkImageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = extent3d,
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT, // MSAA not used by default!
        .tiling = c.VK_IMAGE_TILING_OPTIMAL, // Optimal GPU Format has to be changed to LINEAR for CPU Read
        .usage = usageFlags,
    };
}

fn createAllocatedImageViewInf(format: c.VkFormat, image: c.VkImage, aspectFlags: c.VkImageAspectFlags) c.VkImageViewCreateInfo {
    return c.VkImageViewCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .image = image,
        .format = format,
        .subresourceRange = c.VkImageSubresourceRange{
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
            .aspectMask = aspectFlags,
        },
    };
}
