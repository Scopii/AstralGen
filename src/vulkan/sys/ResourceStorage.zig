const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;
const TextureMeta = @import("../types/res/TextureMeta.zig").TextureMeta;
const FixedList = @import("../../structures/FixedList.zig").FixedList;
const BufferMeta = @import("../types/res/BufferMeta.zig").BufferMeta;
const DescriptorMan = @import("DescriptorMan.zig").DescriptorMan;
const PushData = @import("../types/res/PushData.zig").PushData;
const Texture = @import("../types/res/Texture.zig").Texture;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../configs/renderConfig.zig");
const Context = @import("Context.zig").Context;
const vk = @import("../../modules/vk.zig").c;
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

    buffers: CreateMapArray(Buffer, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = .{},
    textures: CreateMapArray(Texture, rc.TEX_MAX, u32, rc.TEX_MAX, 0) = .{},

    bufZombies: FixedList(Buffer, rc.BUF_MAX) = .{},
    texZombies: FixedList(Texture, rc.TEX_MAX) = .{},

    pub fn init(alloc: Allocator, vma: *const Vma) !ResourceStorage {
        return .{
            .stagingBuffer = try vma.allocStagingBuffer(rc.STAGING_BUF_SIZE),
            .transfers = std.array_list.Managed(Transfer).init(alloc),
        };
    }

    pub fn deinit(self: *ResourceStorage, vma: *const Vma) void {
        vma.freeRawBuffer(self.stagingBuffer.handle, self.stagingBuffer.allocation);
        self.transfers.deinit();

        for (self.buffers.getElements()) |*bufBase| vma.freeBufferBase(bufBase);
        for (self.textures.getElements()) |*texBase| vma.freeTextureBase(texBase);
        for (self.bufZombies.constSlice()) |*bufZombie| vma.freeBufferBase(bufZombie);
        for (self.texZombies.constSlice()) |*texZombie| vma.freeTextureBase(texZombie);
    }

    pub fn resetTransfers(self: *ResourceStorage) void {
        self.stagingOffset = 0;
        self.transfers.clearRetainingCapacity();
    }

    pub fn addBuf(self: *ResourceStorage, bufId: BufferMeta.BufId, buffer: Buffer) void {
        self.buffers.set(bufId.val, buffer);
    }

    pub fn addTex(self: *ResourceStorage, texId: TextureMeta.TexId, tex: Texture) void {
        self.textures.set(texId.val, tex);
    }

    pub fn getBuf(self: *ResourceStorage, bufId: BufferMeta.BufId) !*Buffer {
        if (self.buffers.isKeyUsed(bufId.val) == true) return self.buffers.getPtr(bufId.val) else return error.TextureIdNotUsed;
    }

    pub fn getTex(self: *ResourceStorage, texId: TextureMeta.TexId) !*Texture {
        if (self.textures.isKeyUsed(texId.val) == true) return self.textures.getPtr(texId.val) else return error.TextureIdNotUsed;
    }

    pub fn stageBufferUpdate(self: *ResourceStorage, bufId: BufferMeta.BufId, bytes: []const u8) !void {
        const stagingOffset = self.stagingOffset;
        if (stagingOffset + bytes.len > rc.STAGING_BUF_SIZE) return error.StagingBufferFull;

        try self.transfers.append(.{ .srcOffset = stagingOffset, .dstResId = bufId, .dstOffset = 0, .size = bytes.len });
        self.stagingOffset += (bytes.len + 15) & ~@as(u64, 15);

        const stagingPtr: [*]u8 = @ptrCast(self.stagingBuffer.mappedPtr);
        @memcpy(stagingPtr[stagingOffset..][0..bytes.len], bytes);
    }

    pub fn queueTexDestruction(self: *ResourceStorage, texId: TextureMeta.TexId) !void {
        if (self.textures.isKeyUsed(texId.val)) {
            const tex = self.textures.getPtr(texId.val);
            try self.texZombies.append(tex.*);
            self.textures.removeAtKey(texId.val);
        }
    }

    pub fn queueBufDestruction(self: *ResourceStorage, bufId: BufferMeta.BufId) !void {
        if (self.buffers.isKeyUsed(bufId.val)) {
            const buffer = self.buffers.getPtr(bufId.val);
            try self.bufZombies.append(buffer.*);
            self.buffers.removeAtKey(bufId.val);
        }
    }

    pub fn getTexZombies(self: *ResourceStorage) []const Texture {
        return self.texZombies.constSlice();
    }

    pub fn getBufZombies(self: *ResourceStorage) []const Buffer {
        return self.bufZombies.constSlice();
    }

    pub fn clearTexZombies(self: *ResourceStorage) void {
        self.texZombies.clear();
    }

    pub fn clearBufZombies(self: *ResourceStorage) void {
        self.bufZombies.clear();
    }
};
