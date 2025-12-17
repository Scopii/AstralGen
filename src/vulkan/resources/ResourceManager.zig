const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const vkFn = @import("../../modules/vk.zig");
const Allocator = std.mem.Allocator;
const Context = @import("../Context.zig").Context;
const VkAllocator = @import("../vma.zig").VkAllocator;
const check = @import("../error.zig").check;
const config = @import("../../config.zig");
const Object = @import("../../ecs/EntityManager.zig").Object;
const RENDER_IMG_MAX = config.RENDER_IMG_MAX;

pub const GpuImage = struct {
    allocation: vk.VmaAllocation,
    img: vk.VkImage,
    view: vk.VkImageView,
    extent3d: vk.VkExtent3D,
    format: vk.VkFormat,
    curLayout: u32 = vk.VK_IMAGE_LAYOUT_UNDEFINED,
};

pub const GpuBuffer = struct {
    pub const deviceAddress = u64;
    allocation: vk.VmaAllocation,
    buffer: vk.VkBuffer,
    gpuAddress: deviceAddress,
    size: vk.VkDeviceSize,
    count: u32 = 0,
};

pub const PushConstants = extern struct {
    camPosAndFov: [4]f32,
    camDir: [4]f32,
    runtime: f32,
    dataCount: u32,
    renderImgIndex: u32,
    padding: u32 = 0,
    viewProj: [4][4]f32,
};

pub const ResourceManager = struct {
    cpuAlloc: Allocator,
    gpuAlloc: VkAllocator,
    gpi: vk.VkDevice,
    gpu: vk.VkPhysicalDevice,

    pipeLayout: vk.VkPipelineLayout,

    renderImages: [RENDER_IMG_MAX]?GpuImage = .{null} ** RENDER_IMG_MAX,
    gpuObjects: GpuBuffer = undefined,

    descLayout: vk.VkDescriptorSetLayout,
    imgDescBuffer: GpuBuffer,
    imgDescSize: u32,

    bufferDescSize: u32,

    pub fn init(alloc: Allocator, context: *const Context) !ResourceManager {
        const gpi = context.gpi;
        const gpuAlloc = try VkAllocator.init(context.instance, context.gpi, context.gpu);

        // Query descriptor buffer properties
        var descBufferProps = vk.VkPhysicalDeviceDescriptorBufferPropertiesEXT{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_PROPERTIES_EXT };
        var physDevProps = vk.VkPhysicalDeviceProperties2{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &descBufferProps };
        vk.vkGetPhysicalDeviceProperties2(context.gpu, &physDevProps);

        const imgDescSize: u32 = @intCast(descBufferProps.storageImageDescriptorSize); // Whole gpu memory?
        const bufferDescSize: u32 = @intCast(descBufferProps.storageBufferDescriptorSize);
        // Create descriptor set layout
        const textureBinding = createDescriptorLayoutBinding(0, vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1024, vk.VK_SHADER_STAGE_ALL);
        const objectBinding = createDescriptorLayoutBinding(1, vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, vk.VK_SHADER_STAGE_ALL);
        const descLayout = try createDescriptorLayout(gpi, &.{ textureBinding, objectBinding });
        errdefer vk.vkDestroyDescriptorSetLayout(gpi, descLayout, null);
        // Get the exact size required for this layout from the driver
        var layoutSize: vk.VkDeviceSize = undefined;
        vkFn.vkGetDescriptorSetLayoutSizeEXT.?(gpi, descLayout, &layoutSize);
        // Create descriptor buffer with driver-provided size
        const imgDescBuffer = try createDefinedBuffer(gpuAlloc.handle, gpi, layoutSize, null, .descriptor);

        return .{
            .cpuAlloc = alloc,
            .gpuAlloc = gpuAlloc,
            .gpi = context.gpi,
            .gpu = context.gpu,
            .imgDescSize = imgDescSize,
            .imgDescBuffer = imgDescBuffer,
            .bufferDescSize = bufferDescSize,
            .descLayout = descLayout,
            .pipeLayout = try createPipelineLayout(gpi, descLayout, vk.VK_SHADER_STAGE_ALL, @sizeOf(PushConstants)),
        };
    }

    pub fn deinit(self: *ResourceManager) void {
        self.destroyGpuBuffer(self.gpuObjects);
        for (self.renderImages) |renderImg| if (renderImg != null) self.destroyGpuImageNoId(renderImg.?);
        vk.vmaDestroyBuffer(self.gpuAlloc.handle, self.imgDescBuffer.buffer, self.imgDescBuffer.allocation);
        vk.vkDestroyDescriptorSetLayout(self.gpi, self.descLayout, null);
        self.gpuAlloc.deinit();
        vk.vkDestroyPipelineLayout(self.gpi, self.pipeLayout, null);
    }

    pub fn getRenderImg(self: *ResourceManager, renderId: u8) ?GpuImage {
        return self.renderImages[renderId];
    }

    pub fn getGpuObjects(self: *ResourceManager) GpuBuffer {
        return self.gpuObjects;
    }

    pub fn getRenderImgPtr(self: *ResourceManager, renderId: u8) *GpuImage {
        return &self.renderImages[renderId].?;
    }

    pub fn createGpuImage(self: *ResourceManager, renderId: u8, extent: vk.VkExtent3D, format: vk.VkFormat, usage: vk.VmaMemoryUsage) !void {
        // Extending Flags as Parameters later
        const drawImgUsages = vk.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
            vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT |
            vk.VK_IMAGE_USAGE_STORAGE_BIT |
            vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

        // Allocation from GPU local memory
        const imgInf = createAllocatedImageInf(format, drawImgUsages, extent);
        const imgAllocInf = vk.VmaAllocationCreateInfo{ .usage = usage, .requiredFlags = vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT };

        var img: vk.VkImage = undefined;
        var allocation: vk.VmaAllocation = undefined;
        var view: vk.VkImageView = undefined;
        try check(vk.vmaCreateImage(self.gpuAlloc.handle, &imgInf, &imgAllocInf, &img, &allocation, null), "Could not create Render Image");
        const renderViewInf = createAllocatedImageViewInf(format, img, vk.VK_IMAGE_ASPECT_COLOR_BIT);
        try check(vk.vkCreateImageView(self.gpi, &renderViewInf, null, &view), "Could not create Render Image View");

        self.renderImages[renderId] = GpuImage{ .allocation = allocation, .img = img, .view = view, .extent3d = extent, .format = format };
    }

    pub fn updateImageDescriptor(self: *ResourceManager, index: u32) !void {
        const imgView = self.renderImages[index].?.view;

        // 1. Get the Base Offset for Binding 0 (The Image Array)
        var bindingBaseOffset: vk.VkDeviceSize = 0;
        vkFn.vkGetDescriptorSetLayoutBindingOffsetEXT.?(self.gpi, self.descLayout, 0, &bindingBaseOffset);

        // 2. Prepare Descriptor Info
        const imgInf = vk.VkDescriptorImageInfo{ .sampler = null, .imageView = imgView, .imageLayout = vk.VK_IMAGE_LAYOUT_GENERAL };

        const getInf = vk.VkDescriptorGetInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_GET_INFO_EXT,
            .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
            .data = .{ .pStorageImage = &imgInf },
        };

        // 3. Get Descriptor Data
        var descData: [64]u8 = undefined; // Use safe buffer size
        if (self.imgDescSize > descData.len) return error.DescriptorSizeTooLarge;
        vkFn.vkGetDescriptorEXT.?(self.gpi, &getInf, self.imgDescSize, &descData);

        // 4. Calculate Final Offset
        // Base Offset of the Array + (Index * Size of one Element)
        const finalOffset = bindingBaseOffset + (index * self.imgDescSize);

        // 5. Write to Memory
        var allocVmaInf: vk.VmaAllocationInfo = undefined;
        vk.vmaGetAllocationInfo(self.gpuAlloc.handle, self.imgDescBuffer.allocation, &allocVmaInf);

        const mappedData = @as([*]u8, @ptrCast(allocVmaInf.pMappedData));
        const destPtr = mappedData + finalOffset;

        @memcpy(destPtr[0..self.imgDescSize], descData[0..self.imgDescSize]);
    }

    pub fn createGpuBuffer(self: *ResourceManager, objects: []Object) !void {
        const bufferSize = objects.len * @sizeOf(Object);

        var buffer = try createDefinedBuffer(self.gpuAlloc.handle, self.gpi, bufferSize, null, .testBuffer);
        var allocVmaInf: vk.VmaAllocationInfo = undefined;
        vk.vmaGetAllocationInfo(self.gpuAlloc.handle, buffer.allocation, &allocVmaInf);

        // Check Alignemnt naively (Doesnt catch everything)
        const alignment = @alignOf(Object);
        if (@intFromPtr(allocVmaInf.pMappedData) % alignment != 0) {
            return error.ImproperAlignment;
        }

        const dataPtr: [*]Object = @ptrCast(@alignCast(allocVmaInf.pMappedData));
        @memcpy(dataPtr[0..objects.len], objects);

        buffer.count = @intCast(objects.len);
        self.gpuObjects = buffer;
    }

    pub fn updateObjectBufferDescriptor(self: *ResourceManager) !void {
        const buffer = self.gpuObjects;
        // 1. Get the offset where Binding 1 lives in the descriptor buffer
        var offset: vk.VkDeviceSize = 0;
        vkFn.vkGetDescriptorSetLayoutBindingOffsetEXT.?(self.gpi, self.descLayout, 1, &offset);

        // 2. Prepare the descriptor info
        const addressInf = vk.VkDescriptorAddressInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_ADDRESS_INFO_EXT,
            .address = buffer.gpuAddress,
            .range = buffer.size,
            .format = vk.VK_FORMAT_UNDEFINED,
        };

        const getInf = vk.VkDescriptorGetInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_DESCRIPTOR_GET_INFO_EXT,
            .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .data = .{ .pStorageBuffer = &addressInf },
        };

        // 3. Get the descriptor data from the driver
        // Note: Storage Buffers might have a different descriptor size than Images.
        // Ideally query 'storageBufferDescriptorSize', but usually they are both ~16 bytes.
        // For safety, use a buffer large enough (e.g., 64 bytes).
        var descData: [64]u8 = undefined;
        vkFn.vkGetDescriptorEXT.?(self.gpi, &getInf, self.bufferDescSize, &descData);

        // 4. Write it to the mapped memory
        var allocVmaInf: vk.VmaAllocationInfo = undefined;
        vk.vmaGetAllocationInfo(self.gpuAlloc.handle, self.imgDescBuffer.allocation, &allocVmaInf);

        const mappedData = @as([*]u8, @ptrCast(allocVmaInf.pMappedData));
        const destPtr = mappedData + offset;

        // Copy the descriptor size (usually 16 bytes for buffers)
        @memcpy(destPtr[0..self.bufferDescSize], descData[0..self.bufferDescSize]);
    }

    pub fn updateGpuBuffer(self: *const ResourceManager, bufRef: GpuBuffer, data: []const u8, offset: vk.VkDeviceSize) !void {
        if (offset + data.len > bufRef.size) return error.BufferOverflow;

        var allocVmaInf: vk.VmaAllocationInfo = undefined;
        vk.vmaGetAllocationInfo(self.gpuAlloc.handle, bufRef.allocation, &allocVmaInf);
        const mappedPtr = @as([*]u8, @ptrCast(allocVmaInf.pMappedData));
        @memcpy(mappedPtr[offset .. offset + data.len], data);
    }

    pub fn destroyGpuBuffer(self: *const ResourceManager, bufRef: GpuBuffer) void {
        vk.vmaDestroyBuffer(self.gpuAlloc.handle, bufRef.buffer, bufRef.allocation);
    }

    pub fn destroyGpuImageById(self: *const ResourceManager, renderId: u8) void {
        const gpuImg = self.renderImages[renderId].?;
        vk.vkDestroyImageView(self.gpi, gpuImg.view, null);
        vk.vmaDestroyImage(self.gpuAlloc.handle, gpuImg.img, gpuImg.allocation);
    }

    pub fn destroyGpuImageNoId(self: *const ResourceManager, gpuImg: GpuImage) void {
        vk.vkDestroyImageView(self.gpi, gpuImg.view, null);
        vk.vmaDestroyImage(self.gpuAlloc.handle, gpuImg.img, gpuImg.allocation);
    }
};

fn createDefinedBuffer(vma: vk.VmaAllocator, gpi: vk.VkDevice, size: vk.VkDeviceSize, data: ?[]const u8, bufferType: enum { storage, uniform, descriptor, testBuffer }) !GpuBuffer {
    const bufferUsage: u32 = switch (bufferType) {
        .storage, .testBuffer => vk.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT | vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        .uniform => vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
        .descriptor => vk.VK_BUFFER_USAGE_RESOURCE_DESCRIPTOR_BUFFER_BIT_EXT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
    };
    const memUsage: u32 = switch (bufferType) {
        .storage => vk.VMA_MEMORY_USAGE_GPU_ONLY,
        .uniform, .descriptor, .testBuffer => vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
    };
    const memFlags: u32 = switch (bufferType) {
        .uniform, .descriptor => vk.VMA_ALLOCATION_CREATE_MAPPED_BIT,
        .testBuffer => vk.VMA_ALLOCATION_CREATE_MAPPED_BIT | vk.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
        .storage => 0, // Storage buffers should not be mapped
    };
    return createBuffer(vma, gpi, size, data, bufferUsage, memUsage, memFlags);
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

fn createBuffer(vma: vk.VmaAllocator, gpi: vk.VkDevice, size: vk.VkDeviceSize, data: ?[]const u8, bufferUsage: vk.VkBufferUsageFlags, memUsage: vk.VmaMemoryUsage, memFlags: vk.VmaAllocationCreateFlags) !GpuBuffer {
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
