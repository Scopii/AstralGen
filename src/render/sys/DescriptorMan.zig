const TextureMeta = @import("../types/res/TextureMeta.zig").TextureMeta;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const KeyPool = @import("../../.structures/KeyPool.zig").KeyPool;
const Texture = @import("../types/res/Texture.zig").Texture;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../.configs/renderConfig.zig");
const vkFn = @import("../../.modules/vk.zig").vkFn;
const Context = @import("Context.zig").Context;
const vk = @import("../../.modules/vk.zig").c;
const vhF = @import("../help/Functions.zig");
const vhE = @import("../help/Enums.zig");
const Vma = @import("Vma.zig").Vma;
const std = @import("std");

pub const DescUpdate = struct {
    mainIndex: u32, // slot in descInfos and hostRanges
    specificIndex: u32, // slot in devRanges or imgDescs and imgViews
};

const DESC_MAX = rc.BUF_MAX + (rc.TEX_MAX * 2);
const DESC_POOL_MAX = DESC_MAX * @as(u32, rc.MAX_IN_FLIGHT);

pub const DescriptorMan = struct {
    descHeap: Buffer,
    descStride: u64,
    startOffset: u64,
    driverReservedSize: u64,

    // Descriptor Updates
    descInfos: [DESC_POOL_MAX]vk.VkResourceDescriptorInfoEXT = undefined,
    hostRanges: [DESC_POOL_MAX]vk.VkHostAddressRangeEXT = undefined,

    // Buffer Updates
    bufUpdates: SimpleMap(DescUpdate, rc.BUF_MAX * rc.MAX_IN_FLIGHT, u32, DESC_POOL_MAX, 0) = .{},
    devRanges: [rc.BUF_MAX * @as(u32, rc.MAX_IN_FLIGHT)]vk.VkDeviceAddressRangeEXT = undefined,

    // Image Updates
    texUpdates: SimpleMap(DescUpdate, rc.TEX_MAX * 2 * rc.MAX_IN_FLIGHT, u32, DESC_POOL_MAX, 0) = .{},
    imgViews: [rc.TEX_MAX * 2 * @as(u32, rc.MAX_IN_FLIGHT)]vk.VkImageViewCreateInfo = undefined,
    imgDescs: [rc.TEX_MAX * 2 * @as(u32, rc.MAX_IN_FLIGHT)]vk.VkImageDescriptorInfoEXT = undefined,

    descPool: KeyPool(u31, DESC_POOL_MAX) = .{},

    pub fn init(vma: *const Vma, gpu: vk.VkPhysicalDevice) !DescriptorMan {
        const heapProps = getDescriptorHeapProperties(gpu);
        const driverReservedSize = heapProps.minResourceHeapReservedRange;

        const alignment = heapProps.resourceHeapAlignment;
        const startOffset = (driverReservedSize + (alignment - 1)) & ~(alignment - 1);

        const descStride = @max(heapProps.bufferDescriptorSize, heapProps.imageDescriptorSize);
        const heapSize = rc.MAX_IN_FLIGHT * descStride * DESC_MAX;

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
        return if (self.descPool.isFull() == false) self.descPool.reserveKey() else error.DescPoolFullyUsed;
    }

    pub fn freeDescriptorIndex(self: *DescriptorMan, key: u31) void {
        self.descPool.freeKey(key);
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
            .type = if (bufTyp == .Uniform) vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER else vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, // This is correct!
            .data = .{ .pAddressRange = &self.devRanges[descUpdate.specificIndex] },
        };
    }

    pub fn queueTextureDescriptor(self: *DescriptorMan, texMeta: *const TextureMeta, texture: *Texture) !void {
        const subRange = vhF.createSubresourceRange(texMeta.typ.getImageAspectFlags(), 0, 1, 0, 1);

        switch (texMeta.descriptors) {
            .StorageOnly => {
                try self.queueTextureDescriptorTyp(texMeta, texture, subRange, vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE);
            },
            .SampledOnly => {
                try self.queueTextureDescriptorTyp(texMeta, texture, subRange, vk.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE);
            },
            .StorageSampled => {
                try self.queueTextureDescriptorTyp(texMeta, texture, subRange, vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE);
                try self.queueTextureDescriptorTyp(texMeta, texture, subRange, vk.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE);
            },
        }
    }

    pub fn queueTextureDescriptorTyp(self: *DescriptorMan, texMeta: *const TextureMeta, texture: *Texture, subRange: vk.VkImageSubresourceRange, descTyp: vk.VkDescriptorType) !void {
        var descUpdate: DescUpdate = undefined;

        switch (descTyp) {
            vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE => {
                if (texture.descIndex == null) texture.descIndex = try self.getFreeDescriptorIndex();
                descUpdate = self.getOrCreateUpdate(texture.descIndex.?, Texture);
            },
            vk.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE => {
                if (texture.sampledDescIndex == null) texture.sampledDescIndex = try self.getFreeDescriptorIndex();
                descUpdate = self.getOrCreateUpdate(texture.sampledDescIndex.?, Texture);
            },
            else => return error.DescTypeInvalid,
        }

        self.imgViews[descUpdate.specificIndex] = vhF.getViewCreateInfo(texture.img, texMeta.viewType, texMeta.typ.getFormat(), subRange);

        self.imgDescs[descUpdate.specificIndex] = vk.VkImageDescriptorInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_DESCRIPTOR_INFO_EXT,
            .pView = &self.imgViews[descUpdate.specificIndex],
            .layout = vk.VK_IMAGE_LAYOUT_GENERAL,
        };

        self.descInfos[descUpdate.mainIndex] = vk.VkResourceDescriptorInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_RESOURCE_DESCRIPTOR_INFO_EXT,
            .type = descTyp,
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
