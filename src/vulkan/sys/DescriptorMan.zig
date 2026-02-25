const DescriptorStorage = @import("DescriptorStorage.zig").DescriptorStorage;
const TextureMeta = @import("../types/res/TextureMeta.zig").TextureMeta;
const FixedList = @import("../../structures/FixedList.zig").FixedList;
const LinkedMap = @import("../../structures/LinkedMap.zig").LinkedMap;
const BufferMeta = @import("../types/res/BufferMeta.zig").BufferMeta;
const TextureBase = @import("../types/res/Texture.zig").Texture;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../configs/renderConfig.zig");
const vhF = @import("../help/Functions.zig");
const vk = @import("../../modules/vk.zig").c;
const vkFn = @import("../../modules/vk.zig");
const vhE = @import("../help/Enums.zig");
const Allocator = std.mem.Allocator;
const Vma = @import("Vma.zig").Vma;
const std = @import("std");

pub const DescriptorMan = struct {
    gpi: vk.VkDevice,
    descHeap: Buffer,

    driverReservedSize: u64,
    descStride: u64,
    startOffset: u64,

    descStorages: [rc.MAX_IN_FLIGHT]DescriptorStorage,

    pub fn init(vma: Vma, gpi: vk.VkDevice, gpu: vk.VkPhysicalDevice) !DescriptorMan {
        const heapProps = getDescriptorHeapProperties(gpu);
        const driverReservedSize = heapProps.minResourceHeapReservedRange;

        const alignment = heapProps.resourceHeapAlignment;
        const startOffset = (driverReservedSize + (alignment - 1)) & ~(alignment - 1);

        const descStride = @max(heapProps.bufferDescriptorSize, heapProps.imageDescriptorSize);
        const heapSize = rc.MAX_IN_FLIGHT * descStride * (rc.RESOURCE_MAX);

        var descStorages: [rc.MAX_IN_FLIGHT]DescriptorStorage = undefined;
        for (0..rc.MAX_IN_FLIGHT) |i| {
            const flight: u32 = @intCast(i);
            descStorages[i] = DescriptorStorage.init(flight * rc.RESOURCE_MAX);
        }

        return .{
            .gpi = gpi,
            .descHeap = try vma.allocDescriptorHeap(startOffset + heapSize),
            .driverReservedSize = driverReservedSize,
            .descStride = descStride,
            .startOffset = startOffset,
            .descStorages = descStorages,
        };
    }

    pub fn deinit(self: *DescriptorMan, vma: *const Vma) void {
        vma.freeBufferRaw(self.descHeap.handle, self.descHeap.allocation);
    }

    pub fn getFreeDescriptorIndex(self: *DescriptorMan, flightId: u8) !u32 {
        return try self.descStorages[flightId].getFreeDescriptorIndex();
    }

    pub fn freeDescriptor(self: *DescriptorMan, descIndex: u32, flightId: u8) void {
        self.descStorages[flightId].freeDescriptor(descIndex);
    }

    pub fn queueTextureDescriptor(self: *DescriptorMan, texMeta: *const TextureMeta, img: vk.VkImage, descIndex: u32, flightId: u8) !void {
        const descStorage = &self.descStorages[flightId];
        try descStorage.queueTextureDescriptor(texMeta, img, self.createHostAddressRange(descIndex));
    }

    pub fn queueBufferDescriptor(self: *DescriptorMan, gpuAddress: u64, size: u64, descIndex: u32, bufTyp: vhE.BufferType, flightId: u8) !void {
        const descStorage = &self.descStorages[flightId];
        try descStorage.queueBufferDescriptor(gpuAddress, size, bufTyp, self.createHostAddressRange(descIndex));
    }

    pub fn updateDescriptors(self: *DescriptorMan, flightId: u8) !void {
        const descStorage = &self.descStorages[flightId];
        const descCount: u32 = @intCast(descStorage.queuedDescInfos.len);
        if (descCount == 0) return;

        const start = if (rc.DESCRIPTOR_DEBUG == true) std.time.microTimestamp() else 0;
        try descStorage.updateDescriptors(self.gpi);

        if (rc.DESCRIPTOR_DEBUG == true) {
            const end = std.time.microTimestamp();
            std.debug.print("Descriptors updated ({}) (flightId {}) {d:.3} ms\n", .{ descCount, flightId, @as(f64, @floatFromInt(end - start)) / 1_000.0 });
        }
    }

    fn createHostAddressRange(self: *DescriptorMan, descIndex: u32) vk.VkHostAddressRangeEXT {
        const finalOffset = self.startOffset + (descIndex * self.descStride);
        const mappedData = @as([*]u8, @ptrCast(self.descHeap.mappedPtr));

        return vk.VkHostAddressRangeEXT{
            .address = mappedData + finalOffset,
            .size = self.descStride,
        };
    }
};

fn getDescriptorHeapProperties(gpu: vk.VkPhysicalDevice) vk.VkPhysicalDeviceDescriptorHeapPropertiesEXT {
    var heapProps = vk.VkPhysicalDeviceDescriptorHeapPropertiesEXT{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_HEAP_PROPERTIES_EXT };
    var physDevProps = vk.VkPhysicalDeviceProperties2{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &heapProps };
    vk.vkGetPhysicalDeviceProperties2(gpu, &physDevProps);
    return heapProps;
}
