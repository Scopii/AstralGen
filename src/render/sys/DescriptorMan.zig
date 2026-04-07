const TextureMeta = @import("../types/res/TextureMeta.zig").TextureMeta;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const SlotMap = @import("../../.structures/SlotMap.zig").SlotMap;
const Texture = @import("../types/res/Texture.zig").Texture;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../.configs/renderConfig.zig");
const Context = @import("Context.zig").Context;
const vk = @import("../../.modules/vk.zig").c;
const vhF = @import("../help/Functions.zig");
const vkFn = @import("../../.modules/vk.zig");
const vhE = @import("../help/Enums.zig");
const Vma = @import("Vma.zig").Vma;
const std = @import("std");

pub const DescUpdate = struct {
    mainIndex: u32, // slot in descInfos and hostRanges
    specificIndex: u32, // slot in devRanges or imgDescs and imgViews
};

pub const DescriptorMan = struct {
    descHeap: Buffer,
    descStride: u64,
    startOffset: u64,
    driverReservedSize: u64,

    // Descriptor Updates
    descInfos: [rc.RESOURCE_MAX]vk.VkResourceDescriptorInfoEXT = undefined,
    hostRanges: [rc.RESOURCE_MAX]vk.VkHostAddressRangeEXT = undefined,

    // Buffer Updates
    bufUpdates: SlotMap(DescUpdate, rc.BUF_MAX * rc.MAX_IN_FLIGHT, u32, rc.BUF_MAX * rc.MAX_IN_FLIGHT, 0) = .{},
    devRanges: [rc.BUF_MAX]vk.VkDeviceAddressRangeEXT = undefined,

    // Image Updates
    texUpdates: SlotMap(DescUpdate, rc.TEX_MAX * rc.MAX_IN_FLIGHT, u32, rc.TEX_MAX * rc.MAX_IN_FLIGHT, 0) = .{},
    imgViews: [rc.TEX_MAX]vk.VkImageViewCreateInfo = undefined,
    imgDescs: [rc.TEX_MAX]vk.VkImageDescriptorInfoEXT = undefined,

    freedDescIndices: FixedList(u31, rc.RESOURCE_MAX) = .{},
    descCount: u31 = 0,

    pub fn init(vma: *const Vma, gpu: vk.VkPhysicalDevice) !DescriptorMan {
        const heapProps = getDescriptorHeapProperties(gpu);
        const driverReservedSize = heapProps.minResourceHeapReservedRange;

        const alignment = heapProps.resourceHeapAlignment;
        const startOffset = (driverReservedSize + (alignment - 1)) & ~(alignment - 1);

        const descStride = @max(heapProps.bufferDescriptorSize, heapProps.imageDescriptorSize);
        const heapSize = rc.MAX_IN_FLIGHT * descStride * (rc.RESOURCE_MAX);

        return .{
            .descHeap = try vma.allocDescriptorHeap(startOffset + heapSize),
            .driverReservedSize = driverReservedSize,
            .descStride = descStride,
            .startOffset = startOffset,
        };
    }

    pub fn deinit(self: *DescriptorMan, vma: *const Vma) void {
        vma.freeBufferRaw(self.descHeap.handle, self.descHeap.allocation);
    }

    pub fn getFreeDescriptorIndex(self: *DescriptorMan) !u31 {
        if (self.freedDescIndices.len > 0) {
            const descIndex = self.freedDescIndices.pop();
            if (descIndex) |index| return index else return error.CouldNotPopDescriptorIndex;
        }
        if (self.descCount >= self.freedDescIndices.buffer.len) return error.DescriptorHeapFull;

        const descIndex = self.descCount;
        self.descCount += 1;
        return descIndex;
    }

    pub fn freeDescriptorIndex(self: *DescriptorMan, index: u31) void {
        self.freedDescIndices.append(index) catch |err| std.debug.print("freeDescriptorIndex failed {}\n", .{err});
    }

    fn getOrCreateUpdate(self: *DescriptorMan, descIndex: u31, comptime T: type) DescUpdate {
        const updates = if (T == Buffer) &self.bufUpdates else &self.texUpdates;
        
        if (updates.isKeyUsed(descIndex)) return updates.getByKey(descIndex);

        const texLen = self.texUpdates.getLength();
        const bufLen = self.bufUpdates.getLength();
        const update = DescUpdate{ .mainIndex = texLen + bufLen, .specificIndex = if (T == Buffer) bufLen else texLen };

        updates.upsert(descIndex, update);
        self.hostRanges[update.mainIndex] = self.createHostAddressRange(descIndex);
        return update;
    }

    pub fn queueBufferDescriptor(self: *DescriptorMan, gpuAddress: u64, size: u64, bufTyp: vhE.BufferType, buffer: *Buffer) !void {
        if (buffer.descIndex == null) buffer.descIndex = try self.getFreeDescriptorIndex();
        const descUpdate = self.getOrCreateUpdate(buffer.descIndex.?, Buffer);

        self.devRanges[descUpdate.specificIndex] = vk.VkDeviceAddressRangeEXT{ .address = gpuAddress, .size = size };
        self.descInfos[descUpdate.mainIndex] = vk.VkResourceDescriptorInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_RESOURCE_DESCRIPTOR_INFO_EXT,
            .type = if (bufTyp == .Uniform) vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER else vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .data = .{ .pAddressRange = &self.devRanges[descUpdate.specificIndex] },
        };
    }

    pub fn queueTextureDescriptor(self: *DescriptorMan, texMeta: *const TextureMeta, texture: *Texture) !void {
        if (texture.descIndex == null) texture.descIndex = try self.getFreeDescriptorIndex();
        const descUpdate = self.getOrCreateUpdate(texture.descIndex.?, Texture);

        self.imgViews[descUpdate.specificIndex] = vhF.getViewCreateInfo(texture.img, texMeta.viewType, texMeta.format, texMeta.subRange);

        self.imgDescs[descUpdate.specificIndex] = vk.VkImageDescriptorInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_DESCRIPTOR_INFO_EXT,
            .pView = &self.imgViews[descUpdate.specificIndex],
            .layout = vk.VK_IMAGE_LAYOUT_GENERAL,
        };

        self.descInfos[descUpdate.mainIndex] = vk.VkResourceDescriptorInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_RESOURCE_DESCRIPTOR_INFO_EXT,
            .type = if (texMeta.texType == .Color) vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE else vk.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
            .data = .{ .pImage = &self.imgDescs[descUpdate.specificIndex] },
        };
    }

    pub fn updateDescriptors(self: *DescriptorMan, gpi: vk.VkDevice, flightId: u8) !void {
        const count = self.bufUpdates.getLength() + self.texUpdates.getLength();
        if (count == 0) return;

        const start = if (rc.DESCRIPTOR_DEBUG == true) std.time.microTimestamp() else 0;
        try vhF.check(vkFn.vkWriteResourceDescriptorsEXT.?(gpi, count, &self.descInfos, &self.hostRanges), "Failed to write Descriptor");

        self.bufUpdates.clear();
        self.texUpdates.clear();

        if (rc.DESCRIPTOR_DEBUG == true and count > 0) {
            const time = @as(f64, @floatFromInt(std.time.microTimestamp() - start)) / 1_000.0;
            std.debug.print("Descriptors updated ({}) (flightId {}) {d:.3} ms\n", .{ count, flightId, time });
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
