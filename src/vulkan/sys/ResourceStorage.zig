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

    pub fn init(alloc: Allocator, vma: *const Vma) !ResourceStorage {
        return .{
            .stagingBuffer = try vma.allocStagingBuffer(rc.STAGING_BUF_SIZE),
            .transfers = std.array_list.Managed(Transfer).init(alloc),
        };
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
