const c = @import("../c.zig");
const std = @import("std");
const Context = @import("Context.zig").Context;
const VkAllocator = @import("vma.zig").VkAllocator;
const check = @import("error.zig").check;
const Allocator = std.mem.Allocator;

pub const Image = struct {
    allocation: c.VmaAllocation,
    image: c.VkImage,
    view: c.VkImageView,
    extent3d: c.VkExtent3D,
    format: c.VkFormat,
    curLayout: u32 = c.VK_IMAGE_LAYOUT_UNDEFINED,
};

pub const BufferReference = struct {
    allocation: c.VmaAllocation,
    buffer: c.VkBuffer,
    deviceAddress: u64, // VkDeviceAddress
    size: c.VkDeviceSize,
};

pub const NewResourceManager = struct {
    cpuAlloc: Allocator,
    gpuAlloc: VkAllocator,
    gpi: c.VkDevice,
    gpu: c.VkPhysicalDevice,

    descBufferAllocation: c.VmaAllocation,
    descBuffer: c.VkBuffer,
    descBufferAddr: c.VkDeviceAddress,
    computeLayout: c.VkDescriptorSetLayout,
    bufferSize: c.VkDeviceSize, // Store actual buffer size for validation

    imageDescSize: u32,

    pub fn init(alloc: Allocator, context: *const Context) !NewResourceManager {
        const gpi = context.gpi;
        const gpuAlloc = try VkAllocator.init(context.instance, context.gpi, context.gpu);

        // Query descriptor buffer properties
        var descBufferProps = c.VkPhysicalDeviceDescriptorBufferPropertiesEXT{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_PROPERTIES_EXT,
        };
        var physDevProps = c.VkPhysicalDeviceProperties2{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,
            .pNext = &descBufferProps,
        };
        c.vkGetPhysicalDeviceProperties2(context.gpu, &physDevProps);
        const imageDescSize: u32 = @intCast(descBufferProps.storageImageDescriptorSize);

        // DESCRIPTOR MANAGER STUFF //

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
        var descBufferAllocation: c.VmaAllocation = undefined;
        try check(c.vmaCreateBuffer(gpuAlloc.handle, &bufferInf, &allocInf, &buffer, &descBufferAllocation, null), "Failed to create descriptor buffer");

        // Get buffer device address
        const addrInf = c.VkBufferDeviceAddressInfo{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
            .buffer = buffer,
        };
        const bufferAddr = c.vkGetBufferDeviceAddress(gpi, &addrInf);

        return .{
            .cpuAlloc = alloc,
            .gpuAlloc = gpuAlloc,
            .gpi = context.gpi,
            .gpu = context.gpu,

            .imageDescSize = imageDescSize,

            .descBuffer = buffer,
            .descBufferAllocation = descBufferAllocation,
            .descBufferAddr = bufferAddr,
            .computeLayout = computeLayout,
            .bufferSize = layoutSize,
        };
    }

    pub fn deinit(self: *NewResourceManager) void {
        c.vmaDestroyBuffer(self.gpuAlloc.handle, self.descBuffer, self.descBufferAllocation);
        c.vkDestroyDescriptorSetLayout(self.gpi, self.computeLayout, null);
        self.gpuAlloc.deinit();
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

    pub fn updateStorageImageDescriptor(self: *NewResourceManager, imageView: c.VkImageView, index: u32) !void {
        const gpi = self.gpi;
        const vkAlloc = self.gpuAlloc.handle;

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

    pub fn createImage(self: *const NewResourceManager, extent: c.VkExtent2D, format: c.VkFormat) !Image {
        const drawImageExtent = c.VkExtent3D{ .width = extent.width, .height = extent.height, .depth = 1 };

        const drawImageUsages = c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
            c.VK_IMAGE_USAGE_TRANSFER_DST_BIT |
            c.VK_IMAGE_USAGE_STORAGE_BIT |
            c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

        //const format = c.VK_FORMAT_R16G16B16A16_SFLOAT;

        // Allocation from GPU local memory
        const imageInf = createAllocatedImageInf(format, drawImageUsages, drawImageExtent);
        const imageAllocInf = c.VmaAllocationCreateInfo{
            .usage = c.VMA_MEMORY_USAGE_GPU_ONLY,
            .requiredFlags = c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        };

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
            .extent3d = drawImageExtent,
            .format = format,
        };
    }

    pub fn updateImageDescriptor(self: *NewResourceManager, imageView: c.VkImageView, index: u32) !void {
        const gpi = self.gpi;
        const vkAlloc = self.gpuAlloc.handle;
        const imageDescSize = self.imageDescSize;

        // Validate offset bounds
        // const requiredSize = index * self.imageDescSize + self.imageDescSize;
        // if (requiredSize > self.bufferSize) {
        //     return error.DescriptorOffsetOutOfBounds;
        // }

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
        if (imageDescSize > descData.len) {
            return error.DescriptorSizeTooLarge;
        }
        c.pfn_vkGetDescriptorEXT.?(gpi, &getInf, imageDescSize, &descData);

        var allocVmaInf: c.VmaAllocationInfo = undefined;
        c.vmaGetAllocationInfo(vkAlloc, self.descBufferAllocation, &allocVmaInf);

        const offset = index * imageDescSize;
        const mappedData = @as([*]u8, @ptrCast(allocVmaInf.pMappedData));
        const destPtr = mappedData + offset;

        @memcpy(destPtr[0..imageDescSize], descData[0..imageDescSize]);
    }

    pub fn createBufferReference(self: *const NewResourceManager, size: c.VkDeviceSize, data: ?[]const u8) !BufferReference {
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

        try check(c.vmaCreateBuffer(self.gpuAlloc.handle, &bufferInfo, &allocInfo, &buffer, &allocation, &allocVmaInfo), "Failed to create buffer reference buffer");

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
    pub fn destroyBufferReference(self: *const NewResourceManager, bufRef: BufferReference) void {
        c.vmaDestroyBuffer(self.gpuAlloc.handle, bufRef.buffer, bufRef.allocation);
    }

    // Add this method to ResourceManager struct
    pub fn createTestDataBuffer(self: *const NewResourceManager, extent: c.VkExtent2D) !BufferReference {
        const bufferSize = extent.width * extent.height * @sizeOf([4]f32);
        const buffer = try self.createBufferReference(bufferSize, null);

        // Initialize with test data - sine wave pattern
        var allocVmaInfo: c.VmaAllocationInfo = undefined;
        c.vmaGetAllocationInfo(self.gpuAlloc.handle, buffer.allocation, &allocVmaInfo);
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
    pub fn updateBufferReference(self: *const NewResourceManager, bufRef: BufferReference, data: []const u8, offset: c.VkDeviceSize) !void {
        if (offset + data.len > bufRef.size) return error.BufferOverflow;

        var allocVmaInfo: c.VmaAllocationInfo = undefined;
        c.vmaGetAllocationInfo(self.gpuAlloc.handle, bufRef.allocation, &allocVmaInfo);

        const mappedPtr = @as([*]u8, @ptrCast(allocVmaInfo.pMappedData));
        @memcpy(mappedPtr[offset .. offset + data.len], data);
    }

    pub fn destroyImage(self: *const NewResourceManager, image: Image) void {
        c.vkDestroyImageView(self.gpi, image.view, null);
        c.vmaDestroyImage(self.gpuAlloc.handle, image.image, image.allocation);
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
