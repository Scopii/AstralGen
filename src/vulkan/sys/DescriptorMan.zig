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

    freedDescIndices: FixedList(u32, rc.RESOURCE_MAX) = .{},

    queuedDescInfos: FixedList(vk.VkResourceDescriptorInfoEXT, rc.RESOURCE_MAX * rc.MAX_IN_FLIGHT) = .{},
    queuedHostRanges: FixedList(vk.VkHostAddressRangeEXT, rc.RESOURCE_MAX * rc.MAX_IN_FLIGHT) = .{},

    imgViewStorage: FixedList(vk.VkImageViewCreateInfo, rc.TEX_MAX * rc.MAX_IN_FLIGHT) = .{},
    imgDescStorage: FixedList(vk.VkImageDescriptorInfoEXT, rc.TEX_MAX * rc.MAX_IN_FLIGHT) = .{},
    devRangeStorage: FixedList(vk.VkDeviceAddressRangeEXT, rc.BUF_MAX * rc.MAX_IN_FLIGHT) = .{},

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
        if (self.freedDescIndices.len > 0) {
            const descIndex = self.freedDescIndices.pop();
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
        try self.freedDescIndices.append(descIndex);
    }

    pub fn queueTextureDescriptor(self: *DescriptorMan, tex: *const Texture, flightId: u8, descIndex: u32) !void {
        const imgViewPtr = try self.imgViewStorage.appendReturnPtr(
            vhF.getViewCreateInfo(tex.base[flightId].img, tex.viewType, tex.format, tex.subRange),
        );

        const imgDescPtr = try self.imgDescStorage.appendReturnPtr(
            vk.VkImageDescriptorInfoEXT{
                .sType = vk.VK_STRUCTURE_TYPE_IMAGE_DESCRIPTOR_INFO_EXT,
                .pView = imgViewPtr,
                .layout = vk.VK_IMAGE_LAYOUT_GENERAL, // to DEPTH_STENCIL_READ_ONLY_OPTIMAL for depth?
            },
        );

        try self.queuedDescInfos.append(
            vk.VkResourceDescriptorInfoEXT{
                .sType = vk.VK_STRUCTURE_TYPE_RESOURCE_DESCRIPTOR_INFO_EXT,
                .type = if (tex.texType == .Color) vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE else vk.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
                .data = .{ .pImage = imgDescPtr },
            },
        );

        try self.queuedHostRanges.append(self.createDescriptorAdressRange(descIndex));
    }

    pub fn queueBufferDescriptor(self: *DescriptorMan, gpuAddress: u64, size: u64, descIndex: u32, bufTyp: vhE.BufferType) !void {
        const devRangePtr = try self.devRangeStorage.appendReturnPtr(
            vk.VkDeviceAddressRangeEXT{
                .address = gpuAddress,
                .size = size,
            },
        );

        try self.queuedDescInfos.append(vk.VkResourceDescriptorInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_RESOURCE_DESCRIPTOR_INFO_EXT,
            .type = if (bufTyp == .Uniform) vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER else vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, // what about other Buffer Types?
            .data = .{ .pAddressRange = devRangePtr },
        });

        try self.queuedHostRanges.append(self.createDescriptorAdressRange(descIndex));
    }

    fn createDescriptorAdressRange(self: *DescriptorMan, descIndex: u32) vk.VkHostAddressRangeEXT {
        const finalOffset = self.startOffset + (descIndex * self.descStride);
        const mappedData = @as([*]u8, @ptrCast(self.descHeap.mappedPtr));

        return vk.VkHostAddressRangeEXT{
            .address = mappedData + finalOffset,
            .size = self.descStride,
        };
    }

    pub fn updateDescriptors(self: *DescriptorMan) !void {
        if (self.queuedDescInfos.len == 0) return;

        const descCount: u32 = @intCast(self.queuedDescInfos.len);
        try vhF.check(vkFn.vkWriteResourceDescriptorsEXT.?(self.gpi, descCount, &self.queuedDescInfos.buffer, &self.queuedHostRanges.buffer), "Failed to write Descriptor");

        self.queuedDescInfos.clear();
        self.queuedHostRanges.clear();

        self.imgViewStorage.clear();
        self.imgDescStorage.clear();
        self.devRangeStorage.clear();

        if (rc.DESCRIPTOR_DEBUG == true) std.debug.print("Descriptors Updated ({})\n", .{descCount});
    }
};

fn getDescriptorHeapProperties(gpu: vk.VkPhysicalDevice) vk.VkPhysicalDeviceDescriptorHeapPropertiesEXT {
    var heapProps = vk.VkPhysicalDeviceDescriptorHeapPropertiesEXT{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_HEAP_PROPERTIES_EXT };
    var physDevProps = vk.VkPhysicalDeviceProperties2{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &heapProps };
    vk.vkGetPhysicalDeviceProperties2(gpu, &physDevProps);
    return heapProps;
}
