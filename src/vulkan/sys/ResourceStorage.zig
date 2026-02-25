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

pub const Transfer = struct {
    srcOffset: u64,
    dstResId: BufferMeta.BufId,
    dstOffset: u64,
    size: u64,
};

pub const ResourceStorage = struct {
    stagingBuffer: Buffer,
    stagingOffset: u64 = 0,
    transfers: std.array_list.Managed(Transfer),

    buffers: LinkedMap(Buffer, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = .{},
    textures: LinkedMap(Texture, rc.TEX_MAX, u32, rc.TEX_MAX, 0) = .{},

    bufZombies: FixedList(Buffer, rc.BUF_MAX) = .{},
    texZombies: FixedList(Texture, rc.TEX_MAX) = .{},

    // Desc
    descInfos: FixedList(vk.VkResourceDescriptorInfoEXT, rc.RESOURCE_MAX) = .{},
    hostRanges: FixedList(vk.VkHostAddressRangeEXT, rc.RESOURCE_MAX) = .{},

    imgViews: FixedList(vk.VkImageViewCreateInfo, rc.TEX_MAX) = .{},
    imgDescs: FixedList(vk.VkImageDescriptorInfoEXT, rc.TEX_MAX) = .{},
    devRanges: FixedList(vk.VkDeviceAddressRangeEXT, rc.BUF_MAX) = .{},

    freedDescIndices: FixedList(u32, rc.RESOURCE_MAX) = .{},
    descCount: u32 = 0,
    startIndex: u32,

    pub fn init(alloc: Allocator, vma: *const Vma, startIndex: u32) !ResourceStorage {
        return .{ .stagingBuffer = try vma.allocStagingBuffer(rc.STAGING_BUF_SIZE), .transfers = std.array_list.Managed(Transfer).init(alloc), .startIndex = startIndex };
    }

    pub fn deinit(self: *ResourceStorage, vma: *const Vma) void {
        vma.freeBufferRaw(self.stagingBuffer.handle, self.stagingBuffer.allocation);
        self.transfers.deinit();

        for (self.buffers.getItems()) |*bufBase| vma.freeBuffer(bufBase);
        for (self.textures.getItems()) |*texBase| vma.freeTexture(texBase);
        for (self.bufZombies.constSlice()) |*bufZombie| vma.freeBuffer(bufZombie);
        for (self.texZombies.constSlice()) |*texZombie| vma.freeTexture(texZombie);
    }

    pub fn resetTransfers(self: *ResourceStorage) void {
        self.stagingOffset = 0;
        self.transfers.clearRetainingCapacity();
    }

    pub fn addBuffer(self: *ResourceStorage, bufId: BufferMeta.BufId, buffer: Buffer) void {
        self.buffers.upsert(bufId.val, buffer);
    }

    pub fn addTexture(self: *ResourceStorage, texId: TextureMeta.TexId, tex: Texture) void {
        self.textures.upsert(texId.val, tex);
    }

    pub fn getBuffer(self: *ResourceStorage, bufId: BufferMeta.BufId) !*Buffer {
        if (self.buffers.isKeyUsed(bufId.val) == true) return self.buffers.getPtrByKey(bufId.val) else return error.BufferIdNotUsed;
    }

    pub fn getTexture(self: *ResourceStorage, texId: TextureMeta.TexId) !*Texture {
        if (self.textures.isKeyUsed(texId.val) == true) return self.textures.getPtrByKey(texId.val) else return error.TextureIdNotUsed;
    }

    pub fn stageBufferUpdate(self: *ResourceStorage, bufId: BufferMeta.BufId, bytes: []const u8) !void {
        const stagingOffset = self.stagingOffset;
        if (stagingOffset + bytes.len > rc.STAGING_BUF_SIZE) return error.StagingBufferFull;

        try self.transfers.append(.{ .srcOffset = stagingOffset, .dstResId = bufId, .dstOffset = 0, .size = bytes.len });
        self.stagingOffset += (bytes.len + 15) & ~@as(u64, 15);

        const stagingPtr: [*]u8 = @ptrCast(self.stagingBuffer.mappedPtr);
        @memcpy(stagingPtr[stagingOffset..][0..bytes.len], bytes);
    }

    pub fn queueTextureKill(self: *ResourceStorage, texId: TextureMeta.TexId) !void {
        if (self.textures.isKeyUsed(texId.val)) {
            const tex = self.textures.getPtrByKey(texId.val);
            try self.texZombies.append(tex.*);
            self.textures.remove(texId.val);
        } else std.debug.print("WARNING: Tried to queue Texture destruction ID {} but ID empty\n", .{texId.val});
    }

    pub fn queueBufferKill(self: *ResourceStorage, bufId: BufferMeta.BufId) !void {
        if (self.buffers.isKeyUsed(bufId.val)) {
            const buffer = self.buffers.getPtrByKey(bufId.val);
            try self.bufZombies.append(buffer.*);
            self.buffers.remove(bufId.val);
        } else std.debug.print("WARNING: Tried to queue Buffer destruction ID {} but ID empty\n", .{bufId.val});
    }

    // Desc
    pub fn getFreeDescriptorIndex(self: *ResourceStorage) !u32 {
        if (self.freedDescIndices.len > 0) {
            const descIndex = self.freedDescIndices.pop();
            if (descIndex) |index| return index else return error.CouldNotPopDescriptorIndex;
        }
        if (self.descCount >= self.freedDescIndices.buffer.len) return error.DescriptorHeapFull;

        const descIndex = self.descCount;
        self.descCount += 1;
        return descIndex + self.startIndex;
    }

    fn freeDescriptor(self: *ResourceStorage, descIndex: u32) void {
        const localIndex = descIndex - self.startIndex;
        if (localIndex >= self.descCount) {
            std.debug.print("Descriptor Index {} is unused and cant be freed\n", .{descIndex});
        }
        self.freedDescIndices.append(descIndex) catch |err| {
            std.debug.print("Descriptor Append Failed {}\n", .{err});
        };
    }

    pub fn queueTextureDescriptor(self: *ResourceStorage, texMeta: *const TextureMeta, img: vk.VkImage, hostAddressRange: vk.VkHostAddressRangeEXT) !void {
        const imgViewPtr = try self.imgViews.appendReturnPtr(
            vhF.getViewCreateInfo(img, texMeta.viewType, texMeta.format, texMeta.subRange),
        );

        const imgDescPtr = try self.imgDescs.appendReturnPtr(
            vk.VkImageDescriptorInfoEXT{
                .sType = vk.VK_STRUCTURE_TYPE_IMAGE_DESCRIPTOR_INFO_EXT,
                .pView = imgViewPtr,
                .layout = vk.VK_IMAGE_LAYOUT_GENERAL, // to DEPTH_STENCIL_READ_ONLY_OPTIMAL for depth?
            },
        );

        try self.descInfos.append(
            vk.VkResourceDescriptorInfoEXT{
                .sType = vk.VK_STRUCTURE_TYPE_RESOURCE_DESCRIPTOR_INFO_EXT,
                .type = if (texMeta.texType == .Color) vk.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE else vk.VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE,
                .data = .{ .pImage = imgDescPtr },
            },
        );

        try self.hostRanges.append(hostAddressRange);
    }

    pub fn queueBufferDescriptor(self: *ResourceStorage, gpuAddress: u64, size: u64, bufTyp: vhE.BufferType, hostAddressRange: vk.VkHostAddressRangeEXT) !void {
        const devRangePtr = try self.devRanges.appendReturnPtr(
            vk.VkDeviceAddressRangeEXT{
                .address = gpuAddress,
                .size = size,
            },
        );

        try self.descInfos.append(vk.VkResourceDescriptorInfoEXT{
            .sType = vk.VK_STRUCTURE_TYPE_RESOURCE_DESCRIPTOR_INFO_EXT,
            .type = if (bufTyp == .Uniform) vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER else vk.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, // what about other Buffer Types?
            .data = .{ .pAddressRange = devRangePtr },
        });

        try self.hostRanges.append(hostAddressRange);
    }

    pub fn updateDescriptors(self: *ResourceStorage, gpi: vk.VkDevice, flightId: u8) !void {
        const descCount: u32 = @intCast(self.descInfos.len);
        if (self.descInfos.len == 0) return;

        const start = if (rc.DESCRIPTOR_DEBUG == true) std.time.microTimestamp() else 0;
        try vhF.check(vkFn.vkWriteResourceDescriptorsEXT.?(gpi, @intCast(self.descInfos.len), &self.descInfos.buffer, &self.hostRanges.buffer), "Failed to write Descriptor");

        self.descInfos.clear();
        self.hostRanges.clear();

        self.imgViews.clear();
        self.imgDescs.clear();
        self.devRanges.clear();

        if (rc.DESCRIPTOR_DEBUG == true and descCount > 0) {
            const time = @as(f64, @floatFromInt(std.time.microTimestamp() - start)) / 1_000.0;
            std.debug.print("Descriptors updated ({}) (flightId {}) {d:.3} ms\n", .{ descCount, flightId, time });
        }
    }

    // New Functions
    pub fn cleanupBuffers(self: *ResourceStorage, vma: Vma) u64 {
        const bufZombies = self.bufZombies.constSlice();
        if (bufZombies.len > 0) {
            for (bufZombies) |*bufZombie| {
                self.freeDescriptor(bufZombie.descIndex);
                vma.freeBuffer(bufZombie);
            }
            self.bufZombies.clear();
        }
        return bufZombies.len;
    }

    pub fn cleanupTextures(self: *ResourceStorage, vma: Vma) u64 {
        const texZombies = self.texZombies.constSlice();
        if (texZombies.len > 0) {
            for (texZombies) |*texZombie| {
                self.freeDescriptor(texZombie.descIndex);
                vma.freeTexture(texZombie);
            }
            self.texZombies.clear();
        }
        return texZombies.len;
    }
};
