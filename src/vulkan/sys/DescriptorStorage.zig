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

pub const DescriptorStorage = struct {
    queuedDescInfos: FixedList(vk.VkResourceDescriptorInfoEXT, rc.RESOURCE_MAX) = .{},
    queuedHostRanges: FixedList(vk.VkHostAddressRangeEXT, rc.RESOURCE_MAX) = .{},

    imgViewStorage: FixedList(vk.VkImageViewCreateInfo, rc.TEX_MAX) = .{},
    imgDescStorage: FixedList(vk.VkImageDescriptorInfoEXT, rc.TEX_MAX) = .{},
    devRangeStorage: FixedList(vk.VkDeviceAddressRangeEXT, rc.BUF_MAX) = .{},

    freedDescIndices: FixedList(u32, rc.RESOURCE_MAX) = .{},
    descCount: u32 = 0,
    startIndex: u32,

    pub fn init(startIndex: u32) DescriptorStorage {
        return .{ .startIndex = startIndex };
    }

    pub fn getFreeDescriptorIndex(self: *DescriptorStorage) !u32 {
        if (self.freedDescIndices.len > 0) {
            const descIndex = self.freedDescIndices.pop();
            if (descIndex) |index| return index else return error.CouldNotPopDescriptorIndex;
        }
        if (self.descCount >= self.freedDescIndices.buffer.len) return error.DescriptorHeapFull;

        const descIndex = self.descCount;
        self.descCount += 1;
        return descIndex + self.startIndex;
    }

    pub fn freeDescriptor(self: *DescriptorStorage, descIndex: u32) void {
        if (descIndex >= self.descCount) {
            std.debug.print("Descriptor Index {} is unused and cant be freed\n", .{descIndex});
        }
        self.freedDescIndices.append(descIndex) catch |err| {
            std.debug.print("Descriptor Append Failed {}\n", .{err});
        };
    }

    pub fn queueTextureDescriptor(self: *DescriptorStorage, texMeta: *const TextureMeta, img: vk.VkImage, hostAddressRange: vk.VkHostAddressRangeEXT) !void {
        const imgViewPtr = try self.imgViewStorage.appendReturnPtr(
            vhF.getViewCreateInfo(img, texMeta.viewType, texMeta.format, texMeta.subRange),
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
                .type = if (texMeta.texType == .Color) vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE else vk.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
                .data = .{ .pImage = imgDescPtr },
            },
        );

        try self.queuedHostRanges.append(hostAddressRange);
    }

    pub fn queueBufferDescriptor(self: *DescriptorStorage, gpuAddress: u64, size: u64, bufTyp: vhE.BufferType, hostAddressRange: vk.VkHostAddressRangeEXT) !void {
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

        try self.queuedHostRanges.append(hostAddressRange);
    }

    pub fn updateDescriptors(self: *DescriptorStorage, gpi: vk.VkDevice) !void {
        try vhF.check(vkFn.vkWriteResourceDescriptorsEXT.?(gpi, @intCast(self.queuedDescInfos.len), &self.queuedDescInfos.buffer, &self.queuedHostRanges.buffer), "Failed to write Descriptor");

        self.queuedDescInfos.clear();
        self.queuedHostRanges.clear();

        self.imgViewStorage.clear();
        self.imgDescStorage.clear();
        self.devRangeStorage.clear();
    }
};
