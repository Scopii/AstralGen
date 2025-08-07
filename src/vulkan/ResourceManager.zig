const std = @import("std");
const c = @import("../c.zig");
const VkAllocator = @import("vma.zig").VkAllocator;
const Context = @import("Context.zig").Context;
const check = @import("error.zig").check;

pub const RenderImage = struct {
    allocation: c.VmaAllocation,
    image: c.VkImage,
    view: c.VkImageView,
    extent3d: c.VkExtent3D,
    format: c.VkFormat,
    curLayout: u32 = c.VK_IMAGE_LAYOUT_UNDEFINED,
};

pub const BufferReference = struct {
    buffer: c.VkBuffer,
    allocation: c.VmaAllocation,
    deviceAddress: u64, // VkDeviceAddress
    size: c.VkDeviceSize,
};

pub const ResourceManager = struct {
    vkAlloc: VkAllocator,
    gpi: c.VkDevice,

    pub fn init(context: *const Context) !ResourceManager {
        return .{
            .vkAlloc = try VkAllocator.init(context.instance, context.gpi, context.gpu),
            .gpi = context.gpi,
        };
    }

    pub fn createBufferReference(self: *const ResourceManager, size: c.VkDeviceSize, data: ?[]const u8) !BufferReference {
        const bufferInfo = c.VkBufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        };

        const allocInfo = c.VmaAllocationCreateInfo{
            .usage = c.VMA_MEMORY_USAGE_CPU_TO_GPU, // For easy updates
            .flags = c.VMA_ALLOCATION_CREATE_MAPPED_BIT | c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
        };

        var buffer: c.VkBuffer = undefined;
        var allocation: c.VmaAllocation = undefined;
        var allocVmaInfo: c.VmaAllocationInfo = undefined;

        try check(c.vmaCreateBuffer(self.vkAlloc.handle, &bufferInfo, &allocInfo, &buffer, &allocation, &allocVmaInfo), "Failed to create buffer reference buffer");

        // Get device address for buffer reference
        const addressInfo = c.VkBufferDeviceAddressInfo{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
            .buffer = buffer,
        };
        const deviceAddress = c.vkGetBufferDeviceAddress(self.gpi, &addressInfo);

        // Initialize with data if provided
        if (data) |initData| {
            const mappedPtr = @as([*]u8, @ptrCast(allocVmaInfo.pMappedData));
            @memcpy(mappedPtr[0..initData.len], initData);
        }

        return BufferReference{
            .buffer = buffer,
            .allocation = allocation,
            .deviceAddress = deviceAddress,
            .size = size,
        };
    }

    // Add this method to ResourceManager struct
    pub fn destroyBufferReference(self: *const ResourceManager, bufRef: BufferReference) void {
        c.vmaDestroyBuffer(self.vkAlloc.handle, bufRef.buffer, bufRef.allocation);
    }

    // Add this method to ResourceManager struct
    pub fn createTestDataBuffer(self: *const ResourceManager, extent: c.VkExtent2D) !BufferReference {
        const bufferSize = extent.width * extent.height * @sizeOf([4]f32);
        const buffer = try self.createBufferReference(bufferSize, null);

        // Initialize with test data - sine wave pattern
        var allocVmaInfo: c.VmaAllocationInfo = undefined;
        c.vmaGetAllocationInfo(self.vkAlloc.handle, buffer.allocation, &allocVmaInfo);
        const dataPtr = @as([*][4]f32, @ptrCast(@alignCast(allocVmaInfo.pMappedData)));

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

    // Add this method for updating buffer data
    pub fn updateBufferReference(self: *const ResourceManager, bufRef: BufferReference, data: []const u8, offset: c.VkDeviceSize) !void {
        if (offset + data.len > bufRef.size) return error.BufferOverflow;

        var allocVmaInfo: c.VmaAllocationInfo = undefined;
        c.vmaGetAllocationInfo(self.vkAlloc.handle, bufRef.allocation, &allocVmaInfo);

        const mappedPtr = @as([*]u8, @ptrCast(allocVmaInfo.pMappedData));
        @memcpy(mappedPtr[offset .. offset + data.len], data);
    }

    pub fn createRenderImage(self: *const ResourceManager, extent: c.VkExtent2D) !RenderImage {
        const drawImageExtent = c.VkExtent3D{ .width = extent.width, .height = extent.height, .depth = 1 };

        const drawImageUsages = c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
            c.VK_IMAGE_USAGE_TRANSFER_DST_BIT |
            c.VK_IMAGE_USAGE_STORAGE_BIT |
            c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

        const format = c.VK_FORMAT_R16G16B16A16_SFLOAT;

        // Allocation from GPU local memory
        const renderImageInf = createAllocatedImageInf(format, drawImageUsages, drawImageExtent);
        const renderImageAllocInf = c.VmaAllocationCreateInfo{
            .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
            .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        };

        var image: c.VkImage = undefined;
        var allocation: c.VmaAllocation = undefined;
        var view: c.VkImageView = undefined;

        try check(c.vmaCreateImage(self.vkAlloc.handle, &renderImageInf, &renderImageAllocInf, &image, &allocation, null), "Could not create Render Image");
        const renderViewInf = createAllocatedImageViewInf(format, image, c.VK_IMAGE_ASPECT_COLOR_BIT);
        try check(c.vkCreateImageView(self.gpi, &renderViewInf, null, &view), "Could not create Render Image View");

        return .{
            .allocation = allocation,
            .image = image,
            .view = view,
            .extent3d = drawImageExtent,
            .format = format,
        };
    }

    pub fn destroyRenderImage(self: *const ResourceManager, image: RenderImage) void {
        c.vkDestroyImageView(self.gpi, image.view, null);
        c.vmaDestroyImage(self.vkAlloc.handle, image.image, image.allocation);
    }

    pub fn deinit(self: *ResourceManager) void {
        self.vkAlloc.deinit();
    }
};

pub fn createAllocatedImageInf(format: c.VkFormat, usageFlags: c.VkImageUsageFlags, extent3d: c.VkExtent3D) c.VkImageCreateInfo {
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

pub fn createAllocatedImageViewInf(format: c.VkFormat, image: c.VkImage, aspectFlags: c.VkImageAspectFlags) c.VkImageViewCreateInfo {
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
