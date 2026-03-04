const TextureMeta = @import("../types/res/TextureMeta.zig").TextureMeta;
const FixedList = @import("../../structures/FixedList.zig").FixedList;
const LinkedMap = @import("../../structures/LinkedMap.zig").LinkedMap;
const BufferMeta = @import("../types/res/BufferMeta.zig").BufferMeta;
const PushData = @import("../types/res/PushData.zig").PushData;
const Texture = @import("../types/res/Texture.zig").Texture;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../configs/renderConfig.zig");
const Context = @import("Context.zig").Context;
const vk = @import("../../modules/vk.zig").c;
const vhF = @import("../help/Functions.zig");
const vkFn = @import("../../modules/vk.zig");
const vhT = @import("../help/Types.zig");
const vhE = @import("../help/Enums.zig");
const Allocator = std.mem.Allocator;
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

    // Global Descriptor Indices
    bufDescIndices: [rc.MAX_IN_FLIGHT]LinkedMap(u32, rc.BUF_MAX, u32, rc.BUF_MAX, 0),
    texDescIndices: [rc.MAX_IN_FLIGHT]LinkedMap(u32, rc.TEX_MAX, u32, rc.TEX_MAX, 0),

    // Descriptor Updates
    descInfos: [rc.RESOURCE_MAX]vk.VkResourceDescriptorInfoEXT = undefined,
    hostRanges: [rc.RESOURCE_MAX]vk.VkHostAddressRangeEXT = undefined,

    // Buffer Updates
    bufUpdates: LinkedMap(DescUpdate, rc.BUF_MAX * rc.MAX_IN_FLIGHT, u32, rc.BUF_MAX * rc.MAX_IN_FLIGHT, 0) = .{},
    devRanges: [rc.BUF_MAX]vk.VkDeviceAddressRangeEXT = undefined,

    // Image Updates
    texUpdates: LinkedMap(DescUpdate, rc.TEX_MAX * rc.MAX_IN_FLIGHT, u32, rc.TEX_MAX * rc.MAX_IN_FLIGHT, 0) = .{},
    imgViews: [rc.TEX_MAX]vk.VkImageViewCreateInfo = undefined,
    imgDescs: [rc.TEX_MAX]vk.VkImageDescriptorInfoEXT = undefined,

    freedDescIndices: FixedList(u32, rc.RESOURCE_MAX) = .{},
    descCount: u32 = 0,

    pub fn init(vma: *const Vma, gpu: vk.VkPhysicalDevice) !DescriptorMan {
        const heapProps = getDescriptorHeapProperties(gpu);
        const driverReservedSize = heapProps.minResourceHeapReservedRange;

        const alignment = heapProps.resourceHeapAlignment;
        const startOffset = (driverReservedSize + (alignment - 1)) & ~(alignment - 1);

        const descStride = @max(heapProps.bufferDescriptorSize, heapProps.imageDescriptorSize);
        const heapSize = rc.MAX_IN_FLIGHT * descStride * (rc.RESOURCE_MAX);

        var bufDescIndices: [rc.MAX_IN_FLIGHT]LinkedMap(u32, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = undefined;
        var texDescIndices: [rc.MAX_IN_FLIGHT]LinkedMap(u32, rc.TEX_MAX, u32, rc.TEX_MAX, 0) = undefined;
        for (0..rc.MAX_IN_FLIGHT) |i| {
            bufDescIndices[i] = .{};
            texDescIndices[i] = .{};
        }

        return .{
            .descHeap = try vma.allocDescriptorHeap(startOffset + heapSize),
            .driverReservedSize = driverReservedSize,
            .descStride = descStride,
            .startOffset = startOffset,
            .bufDescIndices = bufDescIndices,
            .texDescIndices = texDescIndices,
        };
    }

    pub fn deinit(self: *DescriptorMan, vma: *const Vma) void {
        vma.freeBufferRaw(self.descHeap.handle, self.descHeap.allocation);
    }

    pub fn getFreeDescriptorIndex(self: *DescriptorMan) !u32 {
        if (self.freedDescIndices.len > 0) {
            const descIndex = self.freedDescIndices.pop();
            if (descIndex) |index| return index else return error.CouldNotPopDescriptorIndex;
        }
        if (self.descCount >= self.freedDescIndices.buffer.len) return error.DescriptorHeapFull;

        const descIndex = self.descCount;
        self.descCount += 1;
        return descIndex;
    }

    pub fn freeDescriptorIndex(self: *DescriptorMan, index: u32) void {
        self.freedDescIndices.append(index) catch |err| std.debug.print("freeDescriptorIndex failed {}\n", .{err});
    }

    pub fn removeBufferDescriptor(self: *DescriptorMan, bufId: BufferMeta.BufId, flightId: u8) u32 {
        const idx = self.bufDescIndices[flightId].getByKey(bufId.val); // get before removing
        self.bufDescIndices[flightId].remove(bufId.val);
        return idx;
    }

    pub fn removeTextureDescriptor(self: *DescriptorMan, texId: TextureMeta.TexId, flightId: u8) u32 {
        const idx = self.texDescIndices[flightId].getByKey(texId.val);
        self.texDescIndices[flightId].remove(texId.val);
        return idx;
    }

    fn bufferHasDescriptor(self: *DescriptorMan, bufId: BufferMeta.BufId, flightId: u8) bool {
        return self.bufDescIndices[flightId].isKeyUsed(bufId.val);
    }

    fn textureHasDescriptor(self: *DescriptorMan, texId: TextureMeta.TexId, flightId: u8) bool {
        return self.texDescIndices[flightId].isKeyUsed(texId.val);
    }

    pub fn getTextureDescriptor(self: *DescriptorMan, texId: TextureMeta.TexId, flightId: u8) !u32 {
        if (self.texDescIndices[flightId].isKeyUsed(texId.val) == true) return self.texDescIndices[flightId].getByKey(texId.val) else return error.TexIdHasNoDescriptor;
    }

    pub fn getBufferDescriptor(self: *DescriptorMan, bufId: BufferMeta.BufId, flightId: u8) !u32 {
        if (self.bufDescIndices[flightId].isKeyUsed(bufId.val) == true) return self.bufDescIndices[flightId].getByKey(bufId.val) else return error.BufIdHasNoDescriptor;
    }

    fn bufferHasUpdate(self: *DescriptorMan, descIndex: u32) bool {
        return self.bufUpdates.isKeyUsed(descIndex);
    }

    fn textureHasUpdate(self: *DescriptorMan, descIndex: u32) bool {
        return self.texUpdates.isKeyUsed(descIndex);
    }

    fn createTextureUpdate(self: *DescriptorMan, descIndex: u32) DescUpdate {
        const texLen = self.texUpdates.getLength();
        const bufLen = self.bufUpdates.getLength();
        const update = DescUpdate{ .mainIndex = texLen + bufLen, .specificIndex = texLen };
        self.texUpdates.upsert(descIndex, update);
        return update;
    }

    fn createBufferUpdate(self: *DescriptorMan, descIndex: u32) DescUpdate {
        const texLen = self.texUpdates.getLength();
        const bufLen = self.bufUpdates.getLength();
        const update = DescUpdate{ .mainIndex = texLen + bufLen, .specificIndex = bufLen };
        self.bufUpdates.upsert(descIndex, update);
        return update;
    }

    pub fn queueTextureDescriptor(self: *DescriptorMan, texMeta: *const TextureMeta, img: vk.VkImage, texId: TextureMeta.TexId, flightId: u8) !void {
        const hasDesc = self.textureHasDescriptor(texId, flightId);
        const descIndex = if (hasDesc) self.texDescIndices[flightId].getByKey(texId.val) else try self.getFreeDescriptorIndex();

        const hasUpdate = self.textureHasUpdate(descIndex);
        const descUpdate = if (hasUpdate) self.texUpdates.getByKey(descIndex) else self.createTextureUpdate(descIndex);

        self.imgViews[descUpdate.specificIndex] = vhF.getViewCreateInfo(img, texMeta.viewType, texMeta.format, texMeta.subRange);

        const imgDescPtr = &self.imgDescs[descUpdate.specificIndex];
        imgDescPtr.* = .{
            .sType = vk.VK_STRUCTURE_TYPE_IMAGE_DESCRIPTOR_INFO_EXT,
            .pView = &self.imgViews[descUpdate.specificIndex],
            .layout = vk.VK_IMAGE_LAYOUT_GENERAL,
        };

        self.descInfos[descUpdate.mainIndex] = .{
            .sType = vk.VK_STRUCTURE_TYPE_RESOURCE_DESCRIPTOR_INFO_EXT,
            .type = if (texMeta.texType == .Color) vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE else vk.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
            .data = .{ .pImage = imgDescPtr },
        };

        if (!hasUpdate) self.hostRanges[descUpdate.mainIndex] = self.createHostAddressRange(descIndex);
        if (!hasDesc) self.texDescIndices[flightId].upsert(texId.val, descIndex);
    }

    pub fn queueBufferDescriptor(self: *DescriptorMan, gpuAddress: u64, size: u64, bufTyp: vhE.BufferType, bufId: BufferMeta.BufId, flightId: u8) !void {
        const hasDesc = self.bufferHasDescriptor(bufId, flightId);
        const descIndex = if (hasDesc) self.bufDescIndices[flightId].getByKey(bufId.val) else try self.getFreeDescriptorIndex();

        const hasUpdate = self.bufferHasUpdate(descIndex);
        const descUpdate = if (hasUpdate) self.bufUpdates.getByKey(descIndex) else self.createBufferUpdate(descIndex);

        self.devRanges[descUpdate.specificIndex] = .{ .address = gpuAddress, .size = size };

        self.descInfos[descUpdate.mainIndex] = .{
            .sType = vk.VK_STRUCTURE_TYPE_RESOURCE_DESCRIPTOR_INFO_EXT,
            .type = if (bufTyp == .Uniform) vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER else vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER,
            .data = .{ .pAddressRange = &self.devRanges[descUpdate.specificIndex] },
        };
        
        if (!hasUpdate) self.hostRanges[descUpdate.mainIndex] = self.createHostAddressRange(descIndex);
        if (!hasDesc) self.bufDescIndices[flightId].upsert(bufId.val, descIndex);
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
