const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;
const TextureBase = @import("../types/res/TextureBase.zig").TextureBase;
const BufferBase = @import("../types/res/BufferBase.zig").BufferBase;
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
    descHeap: DescriptorBuffer,

    driverReservedSize: u64,
    commonStride: u64,

    storageBufCount: u32 = 0,
    storageBufMap: CreateMapArray(u32, rc.MAX_IN_FLIGHT * rc.BUF_MAX, u32, rc.MAX_IN_FLIGHT * rc.BUF_MAX, 0) = .{},
    storageBufOffset: u64,

    storageImgCount: u32 = 0,
    storageImgMap: CreateMapArray(u32, rc.MAX_IN_FLIGHT * rc.STORAGE_TEX_MAX, u32, rc.MAX_IN_FLIGHT * rc.STORAGE_TEX_MAX, 0) = .{},
    storageImgOffset: u64,

    sampledImgCount: u32 = 0,
    sampledImgMap: CreateMapArray(u32, rc.MAX_IN_FLIGHT * rc.SAMPLED_TEX_MAX, u32, rc.MAX_IN_FLIGHT * rc.SAMPLED_TEX_MAX, 0) = .{},
    sampledImgOffset: u64,

    pub fn init(vma: Vma, gpi: vk.VkDevice, gpu: vk.VkPhysicalDevice) !DescriptorMan {
        const heapProps = getDescriptorHeapProperties(gpu);
        const driverReservedSize = heapProps.minResourceHeapReservedRange;

        const alignment = heapProps.resourceHeapAlignment;
        const dataOffset = (driverReservedSize + (alignment - 1)) & ~(alignment - 1);

        const commonStride = @max(heapProps.bufferDescriptorSize, heapProps.imageDescriptorSize);
        const bufHeapSize = rc.MAX_IN_FLIGHT * rc.BUF_MAX * commonStride;
        const imgHeapSize = rc.MAX_IN_FLIGHT * rc.TEX_MAX * commonStride;

        return .{
            .gpi = gpi,
            .descHeap = try vma.allocDescriptorHeap(dataOffset + bufHeapSize + imgHeapSize),
            .driverReservedSize = driverReservedSize,
            .commonStride = commonStride,
            .storageBufOffset = dataOffset,
            .storageImgOffset = dataOffset + bufHeapSize,
            .sampledImgOffset = dataOffset + bufHeapSize + (rc.STORAGE_TEX_MAX * rc.MAX_IN_FLIGHT * commonStride),
        };
    }

    pub fn deinit(self: *DescriptorMan, vma: Vma) void {
        vma.freeRawBuffer(self.descHeap.handle, self.descHeap.allocation);
    }

    pub fn createBufferDescriptor(self: *DescriptorMan, bufBase: BufferBase, bufTyp: vhE.BufferType) !u32 {
        const descIndex = self.storageBufCount;
        try self.updateBufferDescriptor(bufBase.gpuAddress, bufBase.size, descIndex, bufTyp);
        self.storageBufCount += 1;
        return descIndex;
    }

    pub fn updateBufferDescriptor(self: *DescriptorMan, gpuAddress: u64, size: u64, descIndex: u32, bufTyp: vhE.BufferType) !void {
        const descType: vk.VkDescriptorType = switch (bufTyp) {
            .Uniform => vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            else => vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
        };

        const addressInf = vk.VkDeviceAddressRangeEXT{
            .address = gpuAddress,
            .size = size,
        };
        const resDescInf = vk.VkResourceDescriptorInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_RESOURCE_DESCRIPTOR_INFO_EXT,
            .type = descType, 
            .data = .{ .pAddressRange = &addressInf },
        };
        try self.updateDescriptor(&resDescInf, self.descHeap.mappedPtr, self.storageBufOffset, descIndex, self.commonStride);
    }

    pub fn createStorageTexDescriptor(self: *DescriptorMan, texBase: *const TextureBase) !u32 {
        const descIndex = self.storageImgCount;
        const viewInf = texBase.getViewCreateInfo();

        const imgDescInf = vk.VkImageDescriptorInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_DESCRIPTOR_INFO_EXT,
            .pView = &viewInf,
            .layout = vk.VK_IMAGE_LAYOUT_GENERAL,
        };
        const resDescInf = vk.VkResourceDescriptorInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_RESOURCE_DESCRIPTOR_INFO_EXT,
            .type = vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, // For color/RW images
            .data = .{ .pImage = &imgDescInf },
        };

        try self.updateDescriptor(&resDescInf, self.descHeap.mappedPtr, self.storageImgOffset, descIndex, self.commonStride);
        self.storageImgCount += 1;
        return descIndex;
    }

    pub fn createSampledTexDescriptor(self: *DescriptorMan, texBase: *const TextureBase) !u32 {
        const descIndex = self.sampledImgCount;
        const viewInf = texBase.getViewCreateInfo();

        const imgDescInf = vk.VkImageDescriptorInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_DESCRIPTOR_INFO_EXT,
            .pView = &viewInf,
            .layout = vk.VK_IMAGE_LAYOUT_GENERAL, // Or DEPTH_STENCIL_READ_ONLY_OPTIMAL for depth
        };
        const resDescInf = vk.VkResourceDescriptorInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_RESOURCE_DESCRIPTOR_INFO_EXT,
            .type = vk.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
            .data = .{ .pImage = &imgDescInf },
        };

        try self.updateDescriptor(&resDescInf, self.descHeap.mappedPtr, self.sampledImgOffset, descIndex, self.commonStride);
        self.sampledImgCount += 1;
        return descIndex;
    }

    fn updateDescriptor(self: *DescriptorMan, resDescInf: *const vk.VkResourceDescriptorInfoEXT, mappedPtr: ?*anyopaque, heapOffset: u64, descIndex: u32, descSize: u64) !void {
        const finalOffset = heapOffset + (descIndex * descSize);
        const mappedData = @as([*]u8, @ptrCast(mappedPtr));

        const hostAddrRange = vk.VkHostAddressRangeEXT{
            .address = mappedData + finalOffset,
            .size = descSize,
        };
        try vhF.check(vkFn.vkWriteResourceDescriptorsEXT.?(self.gpi, 1, resDescInf, &hostAddrRange), "Failed to write Descriptor");
    }
};

fn getDescriptorHeapProperties(gpu: vk.VkPhysicalDevice) vk.VkPhysicalDeviceDescriptorHeapPropertiesEXT {
    var heapProps = vk.VkPhysicalDeviceDescriptorHeapPropertiesEXT{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_HEAP_PROPERTIES_EXT };
    var physDevProps = vk.VkPhysicalDeviceProperties2{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &heapProps };
    vk.vkGetPhysicalDeviceProperties2(gpu, &physDevProps);
    return heapProps;
}
