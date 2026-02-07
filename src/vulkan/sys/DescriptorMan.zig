const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;
const FixedList = @import("../../structures/FixedList.zig").FixedList;
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
    descStride: u64,
    startOffset: u64,
    resourceCount: u32 = 0,

    freeList: FixedList(u32, rc.RESOURCE_MAX) = .{},

    pub fn init(vma: Vma, gpi: vk.VkDevice, gpu: vk.VkPhysicalDevice) !DescriptorMan {
        const heapProps = getDescriptorHeapProperties(gpu);
        const driverReservedSize = heapProps.minResourceHeapReservedRange;

        const alignment = heapProps.resourceHeapAlignment;
        const startOffset = (driverReservedSize + (alignment - 1)) & ~(alignment - 1);

        const descStride = @max(heapProps.bufferDescriptorSize, heapProps.imageDescriptorSize);
        const heapSize = rc.MAX_IN_FLIGHT * descStride * (rc.RESOURCE_MAX);

        return .{
            .gpi = gpi,
            .descHeap = try vma.allocDescriptorHeap(startOffset + heapSize),
            .driverReservedSize = driverReservedSize,
            .descStride = descStride,
            .startOffset = startOffset,
        };
    }

    pub fn deinit(self: *DescriptorMan, vma: Vma) void {
        vma.freeRawBuffer(self.descHeap.handle, self.descHeap.allocation);
    }

    pub fn getFreeDescriptorIndex(self: *DescriptorMan) !u32 {
        if (self.freeList.len > 0) {
            const descIndex = self.freeList.pop();
            if (descIndex) |index| return index else return error.CouldNotPopDescriptorIndex;
        }
        if (self.resourceCount >= rc.RESOURCE_MAX) return error.DescriptorHeapFull;

        const descIndex = self.resourceCount;
        self.resourceCount += 1;
        return descIndex;
    }

    pub fn freeDescriptor(self: *DescriptorMan, descIndex: u32) !void {
        if (descIndex >= self.resourceCount) {
            std.debug.print("Descriptor Index {} is unused and cant be freed", .{descIndex});
        }
        try self.freeList.append(descIndex);
    }

    pub fn setTextureDescriptor(self: *DescriptorMan, texBase: *const TextureBase, descIndex: u32, typ: enum {StorageTex, SampledTex}) !void {
        const viewInf = texBase.getViewCreateInfo();

        const imgDescInf = vk.VkImageDescriptorInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_DESCRIPTOR_INFO_EXT,
            .pView = &viewInf,
            .layout = vk.VK_IMAGE_LAYOUT_GENERAL, // try  to DEPTH_STENCIL_READ_ONLY_OPTIMAL for depth?
        };
        const resDescInf = vk.VkResourceDescriptorInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_RESOURCE_DESCRIPTOR_INFO_EXT,
            .type = if (typ == .StorageTex) vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE else vk.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
            .data = .{ .pImage = &imgDescInf },
        };
        try self.setDescriptor(&resDescInf, descIndex);
    }

    pub fn setBufferDescriptor(self: *DescriptorMan, gpuAddress: u64, size: u64, descIndex: u32, bufTyp: vhE.BufferType) !void {
        const addressInf = vk.VkDeviceAddressRangeEXT{
            .address = gpuAddress,
            .size = size,
        };
        const resDescInf = vk.VkResourceDescriptorInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_RESOURCE_DESCRIPTOR_INFO_EXT,
            .type = if (bufTyp == .Uniform) vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER else vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, // what about other Buffer Types?
            .data = .{ .pAddressRange = &addressInf },
        };
        try self.setDescriptor(&resDescInf, descIndex);
    }

    fn setDescriptor(self: *DescriptorMan, resDescInf: *const vk.VkResourceDescriptorInfoEXT, descIndex: u32) !void {
        const finalOffset = self.startOffset + (descIndex * self.descStride);
        const mappedData = @as([*]u8, @ptrCast(self.descHeap.mappedPtr,));

        const hostAddrRange = vk.VkHostAddressRangeEXT{
            .address = mappedData + finalOffset,
            .size = self.descStride,
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
