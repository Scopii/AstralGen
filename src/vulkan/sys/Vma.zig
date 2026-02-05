const TextureBase = @import("../types/res/TextureBase.zig").TextureBase;
const DescriptorBuffer = @import("DescriptorMan.zig").DescriptorBuffer;
const BufferBase = @import("../types/res/BufferBase.zig").BufferBase;
const Texture = @import("../types/res/Texture.zig").Texture;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../configs/renderConfig.zig");
const vkFn = @import("../../modules/vk.zig");
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

    pub fn allocDescriptorHeap(self: *const Vma, size: u64) !DescriptorBuffer {
        const bufInf = vk.VkBufferCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = vk.VK_BUFFER_USAGE_DESCRIPTOR_HEAP_BIT_EXT |
                vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        };
        const allocInf = vk.VmaAllocationCreateInfo{
            .usage = vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
            .flags = vk.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT |
                vk.VMA_ALLOCATION_CREATE_MAPPED_BIT,
        };

        var buffer: vk.VkBuffer = undefined;
        var allocation: vk.VmaAllocation = undefined;
        var allocInfo: vk.VmaAllocationInfo = undefined;

        try vhF.check(vk.vmaCreateBuffer(self.handle, &bufInf, &allocInf, &buffer, &allocation, &allocInfo), "Failed to allocate descriptor heap");
        const addressInf = vk.VkBufferDeviceAddressInfo{ .sType = vk.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO, .buffer = buffer };

        return DescriptorBuffer{
            .handle = buffer,
            .allocation = allocation,
            .mappedPtr = allocInfo.pMappedData,
            .size = size,
            .gpuAddress = vk.vkGetBufferDeviceAddress(self.gpi, &addressInf),
        };
    }

    pub fn allocStagingBuffer(self: *const Vma, size: vk.VkDeviceSize) !BufferBase {
        defer std.debug.print("Created Staging Buffer\n", .{});
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

    pub fn allocDefinedBuffer(self: *const Vma, bufInf: Buffer.BufInf,) !Buffer {
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

        if (bufInf.typ != .Staging) bufferBits |= vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT;

        const memType: vk.VmaMemoryUsage = switch (bufInf.mem) {
            .Gpu => vk.VMA_MEMORY_USAGE_GPU_ONLY,
            .CpuWrite => vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
            .CpuRead => vk.VMA_MEMORY_USAGE_GPU_TO_CPU,
        };

        var memFlags: vk.VmaAllocationCreateFlags = switch (bufInf.mem) {
            .Gpu => 0,
            .CpuWrite, .CpuRead => vk.VMA_ALLOCATION_CREATE_MAPPED_BIT,
        };
        if (bufInf.typ == .Staging) memFlags |= vk.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT;

        var buffer: Buffer = undefined;

        switch (bufInf.update) {
            .Overwrite => {
                const tempBuffer = try self.allocBuffer(bufferByteSize, bufferBits, memType, memFlags);
                for (0..rc.MAX_IN_FLIGHT) |i| buffer.base[i] = tempBuffer;
            },
            .PerFrame => {
                for (0..rc.MAX_IN_FLIGHT) |i| {
                    const tempBuffer = try self.allocBuffer(bufferByteSize, bufferBits, memType, memFlags);
                    buffer.base[i] = tempBuffer;
                }
            },
        }

        buffer.update = bufInf.update;
        buffer.typ = bufInf.typ;
        return buffer;
    }

    pub fn allocBuffer(self: *const Vma, size: vk.VkDeviceSize, bufUse: vk.VkBufferUsageFlags, memUse: vk.VmaMemoryUsage, memFlags: vk.VmaAllocationCreateFlags) !BufferBase {
        const bufInf = vk.VkBufferCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = bufUse,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        };
        var buffer: vk.VkBuffer = undefined;
        var allocation: vk.VmaAllocation = undefined;
        var allocVmaInf: vk.VmaAllocationInfo = undefined;
        const allocCreateInf = vk.VmaAllocationCreateInfo{ .usage = memUse, .flags = memFlags };
        try vhF.check(vk.vmaCreateBuffer(self.handle, &bufInf, &allocCreateInf, &buffer, &allocation, &allocVmaInf), "Failed to create Gpu Buffer");

        var gpuAddress: u64 = 0;
        if ((bufUse & vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT) != 0) {
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

    pub const Image = struct {
        img: vk.VkImage = undefined,
        allocation: vk.VmaAllocation,
        view: vk.VkImageView,
    };

    fn allocImagePacket(self: *Vma, memType: vk.VmaMemoryUsage, imgUse: vk.VkImageUsageFlags, aspectFlags: vk.VkImageAspectFlags, format: c_uint, extent: vk.VkExtent3D) !Image {
        var img: vk.VkImage = undefined;
        var allocation: vk.VmaAllocation = undefined;
        const imgInf = createAllocatedImageInf(format, imgUse, extent);
        const imgAllocInf = vk.VmaAllocationCreateInfo{ .usage = memType, .requiredFlags = vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT };
        try vhF.check(vk.vmaCreateImage(self.handle, &imgInf, &imgAllocInf, &img, &allocation, null), "Could not create Render Image");

        var view: vk.VkImageView = undefined;
        const viewInf = createAllocatedImageViewInf(format, img, aspectFlags);
        try vhF.check(vk.vkCreateImageView(self.gpi, &viewInf, null, &view), "Could not create Render Image View");

        return .{ .allocation = allocation, .img = img, .view = view };
    }

    pub fn allocTexture(self: *Vma, texInf: Texture.TexInf) !Texture {
        const memType: vk.VmaMemoryUsage = switch (texInf.mem) {
            .Gpu => vk.VMA_MEMORY_USAGE_GPU_ONLY,
            .CpuWrite => vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
            .CpuRead => vk.VMA_MEMORY_USAGE_GPU_TO_CPU,
        };

        var texUse: vk.VkImageUsageFlags = vk.VK_IMAGE_USAGE_TRANSFER_SRC_BIT | vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT;
        switch (texInf.typ) {
            .Color => texUse |= vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | vk.VK_IMAGE_USAGE_STORAGE_BIT,
            .Depth, .Stencil => texUse |= vk.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
        }

        const format: vk.VkFormat = switch (texInf.typ) {
            .Color => rc.TEX_COLOR_FORMAT,
            .Depth => rc.TEX_DEPTH_FORMAT,
            .Stencil => vk.VK_FORMAT_S8_UINT,
        };

        const aspectMask: vk.VkImageAspectFlags = switch (texInf.typ) {
            .Color => vk.VK_IMAGE_ASPECT_COLOR_BIT,
            .Depth => vk.VK_IMAGE_ASPECT_DEPTH_BIT,
            .Stencil => vk.VK_IMAGE_ASPECT_STENCIL_BIT,
        };

        const extent = vk.VkExtent3D{ .width = texInf.width, .height = texInf.height, .depth = texInf.depth };

        var tempAllocations: [rc.MAX_IN_FLIGHT]vk.VmaAllocation = undefined;
        var tempBase: [rc.MAX_IN_FLIGHT]TextureBase = undefined;

        switch (texInf.update) {
            .Overwrite => { // Single image shared across all frames
                const imagePacket = try self.allocImagePacket(memType, texUse, aspectMask, format, extent);

                for (0..rc.MAX_IN_FLIGHT) |i| {
                    tempAllocations[i] = imagePacket.allocation;
                    tempBase[i] = .{
                        .img = imagePacket.img,
                        .view = imagePacket.view,
                        .texType = texInf.typ,
                        .extent = extent,
                        .viewInfo = getViewCreateInfo(imagePacket.img, vk.VK_IMAGE_VIEW_TYPE_2D, format, aspectMask),
                    };
                }
            },
            .PerFrame => { // Separate image per frame
                for (0..rc.MAX_IN_FLIGHT) |i| {
                    const imagePacket = try self.allocImagePacket(memType, texUse, aspectMask, format, extent);

                    tempAllocations[i] = imagePacket.allocation;
                    tempBase[i] = .{
                        .img = imagePacket.img,
                        .view = imagePacket.view,
                        .texType = texInf.typ,
                        .extent = extent,
                        .viewInfo = getViewCreateInfo(imagePacket.img, vk.VK_IMAGE_VIEW_TYPE_2D, format, aspectMask),
                    };
                }
            },
        }

        return .{
            .allocation = tempAllocations,
            .base = tempBase,
            .update = texInf.update,
        };
    }

    pub fn freeRawBuffer(self: *const Vma, buffer: vk.VkBuffer, allocation: vk.VmaAllocation) void {
        vk.vmaDestroyBuffer(self.handle, buffer, allocation);
    }

    pub fn freeBuffer(self: *const Vma, buffer: *Buffer) void {
        const count = switch (buffer.update) {
            .Overwrite => 1,
            .PerFrame => rc.MAX_IN_FLIGHT,
        };
        for (0..count) |i| vk.vmaDestroyBuffer(self.handle, buffer.base[@intCast(i)].handle, buffer.base[@intCast(i)].allocation);
    }

    pub fn freeTexture(self: *const Vma, tex: *const Texture) void {
        const count = switch (tex.update) {
            .Overwrite => 1,
            .PerFrame => rc.MAX_IN_FLIGHT,
        };
        for (0..count) |i| {
            vk.vkDestroyImageView(self.gpi, tex.base[@intCast(i)].view, null);
            vk.vmaDestroyImage(self.handle, tex.base[@intCast(i)].img, tex.allocation[@intCast(i)]);
        }
    }
};

fn getViewCreateInfo(image: vk.VkImage, viewType: vk.VkImageViewType, format: vk.VkFormat, aspectMask: vk.VkImageAspectFlags) vk.VkImageViewCreateInfo {
    return vk.VkImageViewCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .image = image,
        .viewType = viewType,
        .format = format,
        .components = .{
            .r = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
            .g = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
            .b = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
            .a = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
        },
        .subresourceRange = .{
            .aspectMask = aspectMask,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
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
