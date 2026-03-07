const TextureMeta = @import("../types/res/TextureMeta.zig").TextureMeta;
const ResourceUpdater = @import("ResourceUpdater.zig").ResourceUpdater;
const LinkedMap = @import("../../structures/LinkedMap.zig").LinkedMap;
const BufferMeta = @import("../types/res/BufferMeta.zig").BufferMeta;
const ResourceHolder = @import("ResourceHolder.zig").ResourceHolder;
const ResourceQueue = @import("ResourceQueue.zig").ResourceQueue;
const DescriptorMan = @import("DescriptorMan.zig").DescriptorMan;
const TextureZombie = @import("ResourceQueue.zig").TextureZombie;
const BufferZombie = @import("ResourceQueue.zig").BufferZombie;
const Texture = @import("../types/res/Texture.zig").Texture;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../configs/renderConfig.zig");
const Context = @import("Context.zig").Context;
const vhT = @import("../help/Types.zig");
const vhE = @import("../help/Enums.zig");
const Allocator = std.mem.Allocator;
const Vma = @import("Vma.zig").Vma;
const std = @import("std");

const TexInf = TextureMeta.TexInf;
const BufInf = BufferMeta.BufInf;
const TexId = TextureMeta.TexId;
const BufId = BufferMeta.BufId;

pub const ResourceRegistry = struct {
    staticHolder: ResourceHolder,
    dynHolders: [rc.MAX_IN_FLIGHT]ResourceHolder,

    bufMetas: LinkedMap(BufferMeta, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = .{},
    texMetas: LinkedMap(TextureMeta, rc.TEX_MAX, u32, rc.TEX_MAX, 0) = .{},

    pub fn init() ResourceRegistry {
        var dynHolders: [rc.MAX_IN_FLIGHT]ResourceHolder = undefined;
        for (0..rc.MAX_IN_FLIGHT) |i| dynHolders[i] = ResourceHolder.init();

        return .{
            .staticHolder = ResourceHolder.init(),
            .dynHolders = dynHolders,
        };
    }

    pub fn deinit(self: *ResourceRegistry, vma: *const Vma) void {
        for (0..rc.MAX_IN_FLIGHT) |i| self.dynHolders[i].deinit(vma);
        self.staticHolder.deinit(vma);
    }

    // Meta

    pub fn addBufferMeta(self: *ResourceRegistry, bufId: BufId, bufMeta: BufferMeta) void {
        self.bufMetas.upsert(bufId.val, bufMeta);
    }

    pub fn addTextureMeta(self: *ResourceRegistry, texId: TexId, texMeta: TextureMeta) void {
        self.texMetas.upsert(texId.val, texMeta);
    }

    pub fn getBufferMeta(self: *ResourceRegistry, bufId: BufId) !*BufferMeta {
        if (self.bufMetas.isKeyUsed(bufId.val) == true) return self.bufMetas.getPtrByKey(bufId.val) else return error.BufferMetaIdNotUsed;
    }

    pub fn getTextureMeta(self: *ResourceRegistry, texId: TexId) !*TextureMeta {
        if (self.texMetas.isKeyUsed(texId.val) == true) return self.texMetas.getPtrByKey(texId.val) else return error.TextureMetaIdNotUsed;
    }

    pub fn removeBufferMeta(self: *ResourceRegistry, bufId: BufId) void {
        self.bufMetas.remove(bufId.val);
    }

    pub fn removeTextureMeta(self: *ResourceRegistry, texId: TexId) void {
        self.texMetas.remove(texId.val);
    }

    // Resources

    pub fn addBuffer(self: *ResourceRegistry, bufId: BufId, buffer: Buffer, updateTyp: vhE.UpdateType, flightId: u8) *Buffer {
        const holder = self.getHolder(updateTyp, flightId);
        holder.addBuffer(bufId, buffer);
        return holder.getBuffer(bufId) catch unreachable;
    }

    pub fn addTexture(self: *ResourceRegistry, texId: TexId, tex: Texture, updateTyp: vhE.UpdateType, flightId: u8) *Texture {
        const holder = self.getHolder(updateTyp, flightId);
        holder.addTexture(texId, tex);
        return holder.getTexture(texId) catch unreachable;
    }

    pub fn getBuffer(self: *ResourceRegistry, bufId: BufId, updateTyp: vhE.UpdateType, flightId: u8, updateSlot: u8) !*Buffer {
        return self.getResHolder(updateTyp, flightId, updateSlot).getBuffer(bufId);
    }

    pub fn getTexture(self: *ResourceRegistry, texId: TexId, updateTyp: vhE.UpdateType, flightId: u8, updateSlot: u8) !*Texture {
        return self.getResHolder(updateTyp, flightId, updateSlot).getTexture(texId);
    }

    pub fn removeBuffer(self: *ResourceRegistry, bufId: BufId, updateTyp: vhE.UpdateType, flightId: u8) ?Buffer {
        return self.getHolder(updateTyp, flightId).removeBuffer(bufId);
    }

    pub fn removeTexture(self: *ResourceRegistry, texId: TexId, updateTyp: vhE.UpdateType, flightId: u8) ?Texture {
        return self.getHolder(updateTyp, flightId).removeTexture(texId);
    }

    pub fn checkBuffer(self: *ResourceRegistry, bufId: BufId, updateTyp: vhE.UpdateType, flightId: u8, updateSlot: u8) ?*Buffer {
        return self.getResHolder(updateTyp, flightId, updateSlot).checkBuffer(bufId);
    }

    pub fn checkTexture(self: *ResourceRegistry, texId: TexId, updateTyp: vhE.UpdateType, flightId: u8, updateSlot: u8) ?*Texture {
        return self.getResHolder(updateTyp, flightId, updateSlot).checkTexture(texId);
    }

    fn getHolder(self: *ResourceRegistry, updateTyp: vhE.UpdateType, flightId: u8) *ResourceHolder {
        return switch (updateTyp) {
            .Rarely => &self.staticHolder,
            .Often, .PerFrame => &self.dynHolders[flightId],
        };
    }

    fn getResHolder(self: *ResourceRegistry, updateTyp: vhE.UpdateType, flightId: u8, updateSlot: u8) *ResourceHolder {
        return switch (updateTyp) {
            .Rarely => &self.staticHolder,
            .Often => &self.dynHolders[updateSlot],
            .PerFrame => &self.dynHolders[flightId],
        };
    }
};