const TextureMeta = @import("../types/res/TextureMeta.zig").TextureMeta;
const LinkedMap = @import("../../structures/LinkedMap.zig").LinkedMap;
const BufferMeta = @import("../types/res/BufferMeta.zig").BufferMeta;
const Texture = @import("../types/res/Texture.zig").Texture;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../configs/renderConfig.zig");
const Vma = @import("Vma.zig").Vma;

pub const ResourceHolder = struct {
    buffers: LinkedMap(Buffer, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = .{},
    textures: LinkedMap(Texture, rc.TEX_MAX, u32, rc.TEX_MAX, 0) = .{},

    pub fn init() ResourceHolder {
        return .{};
    }

    pub fn deinit(self: *ResourceHolder, vma: *const Vma) void {
        for (self.buffers.getItems()) |*bufBase| vma.freeBuffer(bufBase);
        for (self.textures.getItems()) |*texBase| vma.freeTexture(texBase);
    }

    pub fn addBuffer(self: *ResourceHolder, bufId: BufferMeta.BufId, buffer: Buffer) void {
        self.buffers.upsert(bufId.val, buffer);
    }

    pub fn addTexture(self: *ResourceHolder, texId: TextureMeta.TexId, tex: Texture) void {
        self.textures.upsert(texId.val, tex);
    }

    pub fn getBuffer(self: *ResourceHolder, bufId: BufferMeta.BufId) !*Buffer {
        if (self.buffers.isKeyUsed(bufId.val) == true) return self.buffers.getPtrByKey(bufId.val) else return error.BufferIdNotUsed;
    }

    pub fn getTexture(self: *ResourceHolder, texId: TextureMeta.TexId) !*Texture {
        if (self.textures.isKeyUsed(texId.val) == true) return self.textures.getPtrByKey(texId.val) else return error.TextureIdNotUsed;
    }

    pub fn removeBuffer(self: *ResourceHolder, bufId: BufferMeta.BufId) ?Buffer {
        if (self.buffers.isKeyUsed(bufId.val) == true) {
            const buf = self.buffers.getPtrByKey(bufId.val).*;
            self.buffers.remove(bufId.val);
            return buf;
        }
        return null;
    }

    pub fn removeTexture(self: *ResourceHolder, texId: TextureMeta.TexId) ?Texture {
        if (self.textures.isKeyUsed(texId.val) == true) {
            const tex = self.textures.getPtrByKey(texId.val).*;
            self.textures.remove(texId.val);
            return tex;
        }
        return null;
    }
};
