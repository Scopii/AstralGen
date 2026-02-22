const TextureMeta = @import("../types/res/TextureMeta.zig").TextureMeta;
const BufferMeta = @import("../types/res/BufferMeta.zig").BufferMeta;
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

    pub fn allocDescriptorHeap(self: *const Vma, size: vk.VkDeviceSize) !Buffer {
        const bufUse = vk.VK_BUFFER_USAGE_DESCRIPTOR_HEAP_BIT_EXT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT;
        const allocFlags = vk.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT | vk.VMA_ALLOCATION_CREATE_MAPPED_BIT;
        const buf = try self.allocBuffer(size, bufUse, vk.VMA_MEMORY_USAGE_CPU_TO_GPU, allocFlags);
        std.debug.print("Created Descriptor Buffer\n", .{});
        return buf;
    }

    pub fn allocStagingBuffer(self: *const Vma, size: vk.VkDeviceSize) !Buffer {
        const allocFlags = vk.VMA_ALLOCATION_CREATE_MAPPED_BIT | vk.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT;
        const buf = try self.allocBuffer(size, vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT, vk.VMA_MEMORY_USAGE_CPU_ONLY, allocFlags); // TEST CPU_TO_GPU and AUTO
        std.debug.print("Created Staging Buffer\n", .{});
        return buf;
    }

    pub fn printMemoryInfo(self: *const Vma, allocation: vk.VmaAllocation) void {
        var allocInf: vk.VmaAllocationInfo = undefined;
        vk.vmaGetAllocationInfo(self.handle, allocation, &allocInf);
        var memProps: vk.VkPhysicalDeviceMemoryProperties = undefined;
        vk.vkGetPhysicalDeviceMemoryProperties(self.gpu, &memProps);

        const flags = memProps.memoryTypes[allocInf.memoryType].propertyFlags;
        const memory = if ((flags & vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) != 0) "VRAM" else "DRAM";
        const visible = if ((flags & vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) != 0) "Visible" else "hidden";
        std.debug.print("(CPU {s} in {s})\n", .{ visible, memory });
    }

    pub fn createBufferMeta(_: *const Vma, bufInf: BufferMeta.BufInf) BufferMeta {
        return .{
            .typ = bufInf.typ,
            .update = bufInf.update,
            .elementSize = bufInf.elementSize,
            .resize = bufInf.resize,
        };
    }

    pub fn allocDefinedBuffer(self: *const Vma, bufInf: BufferMeta.BufInf) !Buffer {
        const bufByteSize = @as(vk.VkDeviceSize, bufInf.len) * bufInf.elementSize;
        if (bufByteSize == 0) return error.BufferByteSizeIsZero;

        const bufUse = vhF.getBufferUsageFlags(bufInf.typ);
        const memUse = vhF.getMemUsage(bufInf.mem);
        const allocFlags = vhF.getBufferAllocationFlags(bufInf.mem, bufInf.typ);

        return try self.allocBuffer(bufByteSize, bufUse, memUse, allocFlags);
    }

    pub fn allocBuffer(self: *const Vma, size: vk.VkDeviceSize, bufUse: vk.VkBufferUsageFlags, memUse: vk.VmaMemoryUsage, memFlags: vk.VmaAllocationCreateFlags) !Buffer {
        const bufCreateInf = vk.VkBufferCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = bufUse,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        };
        const allocCreateInf = vk.VmaAllocationCreateInfo{
            .usage = memUse,
            .flags = memFlags,
        };

        var buffer: vk.VkBuffer = undefined;
        var allocation: vk.VmaAllocation = undefined;
        var allocVmaInf: vk.VmaAllocationInfo = undefined;
        try vhF.check(vk.vmaCreateBuffer(self.handle, &bufCreateInf, &allocCreateInf, &buffer, &allocation, &allocVmaInf), "Failed to create Gpu Buffer");

        var gpuAddress: u64 = 0;
        if ((bufUse & vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT) != 0) {
            const addressInf = vk.VkBufferDeviceAddressInfo{
                .sType = vk.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO,
                .buffer = buffer,
            };
            gpuAddress = vk.vkGetBufferDeviceAddress(self.gpi, &addressInf);
        }

        return .{
            .handle = buffer,
            .allocation = allocation,
            .mappedPtr = allocVmaInf.pMappedData,
            .size = size,
            .gpuAddress = gpuAddress,
        };
    }

    pub fn createTextureMeta(_: *const Vma, texInf: TextureMeta.TexInf) TextureMeta {
        return .{
            .texType = texInf.typ,
            .update = texInf.update,
            .mem = texInf.mem,
            .resize = texInf.resize,
            .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
            .format = vhF.getImageFormat(texInf.typ),
            .subRange = vhF.createSubresourceRange(vhF.getImageAspectFlags(texInf.typ), 0, 1, 0, 1),
        };
    }

    pub fn allocDefinedTexture(self: *Vma, texInf: TextureMeta.TexInf) !Texture {
        const memUsage = vhF.getMemUsage(texInf.mem);
        const texUse = vhF.getImageUse(texInf.typ);
        const format = vhF.getImageFormat(texInf.typ);
        const aspectFlags = vhF.getImageAspectFlags(texInf.typ);
        const subRange = vhF.createSubresourceRange(aspectFlags, 0, 1, 0, 1);
        const extent = vk.VkExtent3D{ .width = texInf.width, .height = texInf.height, .depth = texInf.depth };

        return try self.allocTexture(memUsage, texUse, format, extent, subRange, vk.VK_IMAGE_VIEW_TYPE_2D);
    }

    fn allocTexture(
        self: *Vma,
        memType: vk.VmaMemoryUsage,
        imgUse: vk.VkImageUsageFlags,
        format: vk.VkFormat,
        extent: vk.VkExtent3D,
        subRange: vk.VkImageSubresourceRange,
        viewType: vk.VkImageViewType,
    ) !Texture {
        var img: vk.VkImage = undefined;
        var allocation: vk.VmaAllocation = undefined;
        const imgInf = createImageInf(format, imgUse, extent, subRange, vk.VK_IMAGE_TYPE_2D);
        const imgAllocInf = vk.VmaAllocationCreateInfo{ .usage = memType, .requiredFlags = vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT };
        try vhF.check(vk.vmaCreateImage(self.handle, &imgInf, &imgAllocInf, &img, &allocation, null), "Could not create Render Image");

        var view: vk.VkImageView = undefined;
        const viewInf = vhF.getViewCreateInfo(img, viewType, format, subRange);
        try vhF.check(vk.vkCreateImageView(self.gpi, &viewInf, null, &view), "Could not create Render Image View");

        return .{
            .allocation = allocation,
            .img = img,
            .view = view,
            .extent = extent,
        };
    }

    pub fn freeRawBuffer(self: *const Vma, buffer: vk.VkBuffer, allocation: vk.VmaAllocation) void {
        vk.vmaDestroyBuffer(self.handle, buffer, allocation);
    }

    pub fn freeBufferBase(self: *const Vma, bufBase: *const Buffer) void {
        vk.vmaDestroyBuffer(self.handle, bufBase.handle, bufBase.allocation);
    }

    pub fn freeTextureBase(self: *const Vma, texBase: *const Texture) void {
        vk.vkDestroyImageView(self.gpi, texBase.view, null);
        vk.vmaDestroyImage(self.handle, texBase.img, texBase.allocation);
    }
};

fn createImageInf(format: vk.VkFormat, usageFlags: vk.VkImageUsageFlags, extent3d: vk.VkExtent3D, subRange: vk.VkImageSubresourceRange, imgType: vk.VkImageType) vk.VkImageCreateInfo {
    return vk.VkImageCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = imgType,
        .format = format,
        .extent = extent3d,
        .mipLevels = subRange.levelCount,
        .arrayLayers = subRange.layerCount,
        .samples = vk.VK_SAMPLE_COUNT_1_BIT, // MSAA not used by default!
        .tiling = vk.VK_IMAGE_TILING_OPTIMAL, // Optimal GPU Format has to be changed to LINEAR for CPU Read
        .usage = usageFlags,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 0,
        .pQueueFamilyIndices = null,
        .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
    };
}
