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
    resourceCount: u32 = 0,

    freedDescIndices: FixedList(u32, rc.RESOURCE_MAX * rc.MAX_IN_FLIGHT) = .{},
    descStorages: [rc.MAX_IN_FLIGHT]DescriptorStorage,

    pub fn init(vma: Vma, gpi: vk.VkDevice, gpu: vk.VkPhysicalDevice) !DescriptorMan {
        const heapProps = getDescriptorHeapProperties(gpu);
        const driverReservedSize = heapProps.minResourceHeapReservedRange;

        const alignment = heapProps.resourceHeapAlignment;
        const startOffset = (driverReservedSize + (alignment - 1)) & ~(alignment - 1);

        const descStride = @max(heapProps.bufferDescriptorSize, heapProps.imageDescriptorSize);
        const heapSize = rc.MAX_IN_FLIGHT * descStride * (rc.RESOURCE_MAX);

        var descStorages: [rc.MAX_IN_FLIGHT]DescriptorStorage = undefined;
        for (0..rc.MAX_IN_FLIGHT) |i| descStorages[i] = .{};

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
        vma.freeRawBuffer(self.descHeap.handle, self.descHeap.allocation);
    }

    pub fn getFreeDescriptorIndex(self: *DescriptorMan) !u32 {
        if (self.freedDescIndices.len > 0) {
            const descIndex = self.freedDescIndices.pop();
            if (descIndex) |index| return index else return error.CouldNotPopDescriptorIndex;
        }
        if (self.resourceCount >= self.freedDescIndices.buffer.len) return error.DescriptorHeapFull;

        const descIndex = self.resourceCount;
        self.resourceCount += 1;
        return descIndex;
    }

    pub fn freeDescriptor(self: *DescriptorMan, descIndex: u32) void {
        if (descIndex >= self.resourceCount) {
            std.debug.print("Descriptor Index {} is unused and cant be freed\n", .{descIndex});
        }
        self.freedDescIndices.append(descIndex) catch |err| {
            std.debug.print("Descriptor Append Failed {}\n", .{err});
        };
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
