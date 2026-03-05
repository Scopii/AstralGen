const TextureMeta = @import("../types/res/TextureMeta.zig").TextureMeta;
const FixedList = @import("../../structures/FixedList.zig").FixedList;
const LinkedMap = @import("../../structures/LinkedMap.zig").LinkedMap;
const BufferMeta = @import("../types/res/BufferMeta.zig").BufferMeta;
const Texture = @import("../types/res/Texture.zig").Texture;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../configs/renderConfig.zig");

pub const BufferZombie = struct { buf: Buffer, descIndex: u32 };
pub const TextureZombie = struct { tex: Texture, descIndex: u32 };

pub const ResourceQueue = struct {
    bufCreations: LinkedMap(BufferMeta.BufInf, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = .{},
    texCreations: LinkedMap(TextureMeta.TexInf, rc.TEX_MAX, u32, rc.TEX_MAX, 0) = .{},

    bufDeletions: FixedList(BufferZombie, rc.BUF_MAX) = .{},
    texDeletions: FixedList(TextureZombie, rc.TEX_MAX) = .{},


    pub fn addBufferCreation(self: *ResourceQueue, bufInf: BufferMeta.BufInf) void {
        self.bufCreations.upsert(bufInf.id.val, bufInf);
    }

    pub fn addTextureCreation(self: *ResourceQueue, texInf: TextureMeta.TexInf) void {
        self.texCreations.upsert(texInf.id.val, texInf);
    }

    pub fn addBufferDeletion(self: *ResourceQueue, bufZom: BufferZombie) !void {
        try self.bufDeletions.append(bufZom);
    }

    pub fn addTextureDeletion(self: *ResourceQueue, texZom: TextureZombie) !void {
        try self.texDeletions.append(texZom);
    }

    pub fn getBufferCreations(self: *ResourceQueue) []BufferMeta.BufInf {
        return self.bufCreations.getItems();
    }

    pub fn getTextureCreations(self: *ResourceQueue) []TextureMeta.TexInf {
        return self.texCreations.getItems();
    }

    pub fn getBufferDeletions(self: *ResourceQueue) []BufferZombie {
        return self.bufDeletions.slice();
    }

    pub fn getTextureDeletions(self: *ResourceQueue) []TextureZombie {
        return self.texDeletions.slice();
    }

    pub fn invalidateBufferCreation(self: *ResourceQueue, bufId: BufferMeta.BufId) void {
        if (self.bufCreations.isKeyUsed(bufId.val) == true) self.bufCreations.remove(bufId.val);
    }

    pub fn invalidateTextureCreation(self: *ResourceQueue, texId: TextureMeta.TexId) void {
        if (self.texCreations.isKeyUsed(texId.val) == true) self.texCreations.remove(texId.val);
    }

    pub fn checkBufferCreation(self: *ResourceQueue, bufId: BufferMeta.BufId) ?*BufferMeta.BufInf {
        if (self.bufCreations.isKeyUsed(bufId.val) == true) return self.bufCreations.getPtrByKey(bufId.val) else return null;
    }

    pub fn checkTextureCreation(self: *ResourceQueue, texId: TextureMeta.TexId) ?*TextureMeta.TexInf {
        if (self.texCreations.isKeyUsed(texId.val) == true) return self.texCreations.getPtrByKey(texId.val) else return null;
    }

    pub fn clear(self: *ResourceQueue) void {
        self.bufCreations.clear();
        self.texCreations.clear();
        self.bufDeletions.clear();
        self.texDeletions.clear();
    }
};
