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

const QUEUE_COUNT = (rc.MAX_IN_FLIGHT + 1);

pub const ResourceMan = struct {
    vma: Vma,
    alloc: Allocator,
    descMan: DescriptorMan,

    queues: [QUEUE_COUNT]ResourceQueue,

    staticHolder: ResourceHolder,
    dynHolders: [rc.MAX_IN_FLIGHT]ResourceHolder,
    resUpdaters: [rc.MAX_IN_FLIGHT]ResourceUpdater,

    bufMetas: LinkedMap(BufferMeta, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = .{},
    texMetas: LinkedMap(TextureMeta, rc.TEX_MAX, u32, rc.TEX_MAX, 0) = .{},

    pub fn init(alloc: Allocator, context: *const Context) !ResourceMan {
        const vma = try Vma.init(context.instance, context.gpi, context.gpu);

        var dynHolders: [rc.MAX_IN_FLIGHT]ResourceHolder = undefined;
        var resUpdaters: [rc.MAX_IN_FLIGHT]ResourceUpdater = undefined;

        for (0..rc.MAX_IN_FLIGHT) |i| {
            dynHolders[i] = ResourceHolder.init();
            resUpdaters[i] = try ResourceUpdater.init(&vma);
        }

        var queues: [QUEUE_COUNT]ResourceQueue = undefined;
        for (0..QUEUE_COUNT) |i| queues[i] = .{};

        return .{
            .vma = vma,
            .alloc = alloc,
            .descMan = try DescriptorMan.init(&vma, context.gpu),
            .queues = queues,
            .staticHolder = ResourceHolder.init(),
            .dynHolders = dynHolders,
            .resUpdaters = resUpdaters,
        };
    }

    pub fn deinit(self: *ResourceMan) void {
        for (0..rc.MAX_IN_FLIGHT) |i| {
            self.dynHolders[i].deinit(&self.vma);
            self.resUpdaters[i].deinit(&self.vma);
        }
        for (&self.queues) |*queue| {
            for (queue.getBufferDeletions()) |*bufZom| self.destroyBuffer(bufZom);
            for (queue.getTextureDeletions()) |*texZom| self.destroyTexture(texZom);
        }
        self.staticHolder.deinit(&self.vma);
        self.descMan.deinit(&self.vma);
        self.vma.deinit();
    }

    pub fn getResourceUpdater(self: *ResourceMan, flightId: u8) *ResourceUpdater {
        return &self.resUpdaters[flightId];
    }

    fn getBufferDataPtr(self: *ResourceMan, bufId: BufferMeta.BufId, comptime T: type, flightId: u8) !*T {
        const buffer = try self.getBuffer(bufId, flightId);
        if (buffer.mappedPtr) |ptr| {
            return @as(*T, @ptrCast(@alignCast(ptr)));
        }
        return error.BufferNotHostVisible;
    }

    fn printReadbackBuffer(self: *ResourceMan, bufId: BufferMeta.BufId, comptime T: type, flightId: u8) !void {
        const readbackPtr = try self.getBufferDataPtr(bufId, T, flightId);
        std.debug.print("Readback: {}\n", .{readbackPtr.*});
    }

    pub fn update(self: *ResourceMan, flightId: u8, curFrame: u64) !void {
        const start = if (rc.RESOURCE_DEBUG == true) std.time.microTimestamp() else 0;
        if (rc.GPU_READBACK == true) try self.printReadbackBuffer(rc.readbackSB.id, vhT.ReadbackData, flightId);

        const queueId = curFrame % QUEUE_COUNT;
        const curQueue = &self.queues[queueId];

        const bufDeletions = curQueue.getBufferDeletions();
        const texDeletions = curQueue.getTextureDeletions();
        const bufCreations = curQueue.getBufferCreations();
        const texCreations = curQueue.getTextureCreations();

        for (bufDeletions) |*bufZom| self.destroyBuffer(bufZom);
        for (texDeletions) |*texZom| self.destroyTexture(texZom);
        for (bufCreations) |bufInf| try self.createBuffer(bufInf, flightId);
        for (texCreations) |texInf| try self.createTexture(texInf, flightId);

        curQueue.clear();

        if (rc.RESOURCE_DEBUG == true and bufDeletions.len + texDeletions.len + bufCreations.len + texCreations.len > 0) {
            const time = @as(f64, @floatFromInt(std.time.microTimestamp() - start)) / 1_000.0;
            std.debug.print("ResMan Updated! (Deletions Buf {} Tex {}) (Creations Buf {} Tex {}) ", .{ bufDeletions.len, texDeletions.len, bufCreations.len, texCreations.len });
            std.debug.print("(Frame {}) (FlightId {}) {d:.3} ms\n", .{ curFrame, flightId, time });
        }
        try self.descMan.updateDescriptors(self.vma.gpi, flightId);
    }

    // Getters
    pub fn getBufferDescriptor(self: *ResourceMan, bufId: BufId, flightId: u8) !u32 {
        const bufMeta = try self.getBufferMeta(bufId);
        const realIndex = switch (bufMeta.update) {
            .Overwrite => 0,
            .PerFrame => if (bufMeta.typ == .Indirect) flightId else bufMeta.updateSlot,
        };
        return (try self.descMan.getBufferDescriptor(bufId, realIndex));
    }
    pub fn getTextureDescriptor(self: *ResourceMan, texId: TexId, flightId: u8) !u32 {
        const texMeta = try self.getTextureMeta(texId);
        const realIndex = switch (texMeta.update) {
            .Overwrite => 0,
            .PerFrame => flightId,
        };
        return (try self.descMan.getTextureDescriptor(texId, realIndex));
    }

    pub fn getBuffer(self: *ResourceMan, bufId: BufId, flightId: u8) !*Buffer {
        const bufMeta = try self.getBufferMeta(bufId);
        return switch (bufMeta.update) {
            .Overwrite => try self.staticHolder.getBuffer(bufId),
            .PerFrame => if (bufMeta.typ == .Indirect) try self.dynHolders[flightId].getBuffer(bufId) else try self.dynHolders[bufMeta.updateSlot].getBuffer(bufId),
        };
    }

    pub fn getTexture(self: *ResourceMan, texId: TexId, flightId: u8) !*Texture {
        const texMeta = try self.getTextureMeta(texId);
        return switch (texMeta.update) {
            .Overwrite => try self.staticHolder.getTexture(texId),
            .PerFrame => try self.dynHolders[flightId].getTexture(texId),
        };
    }

    // Adding Tickets
    pub fn addBufferResource(self: *ResourceMan, bufInf: BufInf, curFrame: u64) void {
        self.bufMetas.upsert(bufInf.id.val, self.vma.createBufferMeta(bufInf));

        for (0..bufInf.update.getCount()) |i| {
            self.queues[(curFrame + i) % QUEUE_COUNT].addBufferCreation(bufInf);
        }
        if (rc.RESOURCE_DEBUG == true) std.debug.print("Buffer added! (ID {}) (Frame {}) ({}) ({})\n", .{ bufInf.id.val, curFrame, bufInf.typ, bufInf.update });
    }

    pub fn addTextureResource(self: *ResourceMan, texInf: TexInf, curFrame: u64) void {
        self.texMetas.upsert(texInf.id.val, self.vma.createTextureMeta(texInf));

        for (0..texInf.update.getCount()) |i| {
            self.queues[(curFrame + i) % QUEUE_COUNT].addTextureCreation(texInf);
        }
        if (rc.RESOURCE_DEBUG == true) std.debug.print("Texture added! (ID {}) (Frame {}) ({}) ({})\n", .{ texInf.id.val, curFrame, texInf.typ, texInf.update });
    }

    pub fn updateBufferResource(self: *ResourceMan, bufId: BufId, data: anytype, curFrame: u64, flightId: u8) !void { // Could maybe be implemented better
        const bufMeta = try self.getBufferMeta(bufId);
        const bytes = try convertToByteSlice(data);
        const newCount: u32 = @intCast(bytes.len / bufMeta.elementSize);

        bufMeta.updateSlot = (bufMeta.updateSlot + 1) % bufMeta.update.getCount(); // advance on each update
        const realFlight = switch (bufMeta.update) {
            .Overwrite => 0,
            .PerFrame => bufMeta.updateSlot, // slot not flightId
        };

        const resHolder = switch (bufMeta.update) {
            .Overwrite => &self.staticHolder,
            .PerFrame => &self.dynHolders[bufMeta.updateSlot],
        };

        // Check if the buffer is actively alive for THIS flight
        if (resHolder.buffers.isKeyUsed(bufId.val)) { // DEDICATED FUNCTION?
            const buf = try resHolder.getBuffer(bufId);
            var needsRealloc = false;

            switch (bufMeta.resize) {
                .Block => {
                    if (bytes.len > buf.size) return error.BufferBaseTooSmallForUpdate;
                },
                .Grow => {
                    if (bytes.len > buf.size) needsRealloc = true;
                },
                .Fit => {
                    if (bytes.len != buf.size) needsRealloc = true;
                },
            }

            if (needsRealloc) {
                // Nuke it everywhere (Holders and Queues) and recreate
                const newInf = BufInf{
                    .id = bufId,
                    .mem = bufMeta.mem, // Make sure BufferMeta has this!
                    .elementSize = bufMeta.elementSize,
                    .len = newCount,
                    .typ = bufMeta.typ,
                    .update = bufMeta.update,
                    .resize = bufMeta.resize,
                };
                // Nuke everything (murders active, aborts unborn) and respawns
                try self.removeBufferResource(bufId, curFrame);
                self.addBufferResource(newInf, curFrame);
            } else if (buf.curCount != newCount) {
                // It fits in memory. Update descriptor.
                const newByteSize = newCount * bufMeta.elementSize;
                try self.descMan.queueBufferDescriptor(buf.gpuAddress, newByteSize, bufMeta.typ, bufId, realFlight);
                buf.curCount = newCount;

                // Update any unborn tickets in the queues so they spawn correctly
                for (0..QUEUE_COUNT) |i| {
                    if (self.queues[i].checkBufferCreation(bufId)) |bufInf| bufInf.len = newCount;
                }
            }
        } else {
            // Not alive. MUST be an unborn ticket. Update all tickets.
            for (0..QUEUE_COUNT) |i| {
                if (self.queues[i].checkBufferCreation(bufId)) |bufInf| {
                    switch (bufMeta.resize) {
                        .Block => {
                            if (newCount > bufInf.len) return error.BufferBaseTooSmallForUpdate;
                        },
                        .Grow => {
                            if (newCount > bufInf.len) bufInf.len = newCount;
                        },
                        .Fit => {
                            bufInf.len = newCount;
                        },
                    }
                }
            }
        }
        try self.resUpdaters[flightId].stageBufferUpdate(bufId, bytes, bufMeta.updateSlot);
    }

    pub fn resizeTextureResource(self: *ResourceMan, texId: TexId, newWidth: u32, newHeight: u32, curFrame: u64, flightId: u8) !void {
        const texMeta = try self.getTextureMeta(texId);
        const resHolder = switch (texMeta.update) {
            .Overwrite => &self.staticHolder,
            .PerFrame => &self.dynHolders[flightId],
        };

        if (resHolder.textures.isKeyUsed(texId.val)) {
            // Alive! Reallocate everywhere if size changed.
            const tex = try resHolder.getTexture(texId);
            if (tex.extent.width != newWidth or tex.extent.height != newHeight) {
                const newInf = TexInf{
                    .id = texId,
                    .mem = texMeta.mem,
                    .typ = texMeta.texType,
                    .width = newWidth,
                    .height = newHeight,
                    .depth = 1,
                    .update = texMeta.update,
                    .resize = texMeta.resize,
                };
                try self.removeTextureResource(texId, curFrame);
                self.addTextureResource(newInf, curFrame);
            }
        } else {
            // Unborn! Just tweak pending tickets.
            for (0..QUEUE_COUNT) |i| {
                if (self.queues[i].checkTextureCreation(texId)) |texInf| {
                    texInf.width = newWidth;
                    texInf.height = newHeight;
                }
            }
        }
    }

    // pub fn updateTextureResource(_: *ResourceMan2, _: TexId) void {} // Not needed yet

    pub fn removeBufferResource(self: *ResourceMan, bufId: BufId, curFrame: u64) !void {
        if (self.bufMetas.isKeyUsed(bufId.val) == false) return error.BufferMetaIdNotUsed;
        const bufMeta = self.bufMetas.getPtrByKey(bufId.val);

        // Kill
        for (0..bufMeta.update.getCount()) |flightId| {
            const resHolder = switch (bufMeta.update) {
                .Overwrite => &self.staticHolder,
                .PerFrame => &self.dynHolders[flightId],
            };

            if (resHolder.removeBuffer(bufId)) |buf| {
                const descIndex = self.descMan.removeBufferDescriptor(bufId, @intCast(flightId));
                try self.queues[(curFrame + rc.MAX_IN_FLIGHT) % QUEUE_COUNT].addBufferDeletion(.{ .buf = buf, .descIndex = descIndex });
            }
        }
        // Abort
        for (0..QUEUE_COUNT) |i| {
            self.queues[i].invalidateBufferCreation(bufId);
        }
        if (rc.RESOURCE_DEBUG == true) std.debug.print("Buffer Removed! (ID {}) (Frame {})\n", .{ bufId.val, curFrame });
    }

    pub fn removeTextureResource(self: *ResourceMan, texId: TexId, curFrame: u64) !void {
        if (self.texMetas.isKeyUsed(texId.val) == false) return error.TextureMetaIdNotUsed;
        const texMeta = self.texMetas.getPtrByKey(texId.val);

        // Kill
        for (0..texMeta.update.getCount()) |flightId| {
            const resHolder = switch (texMeta.update) {
                .Overwrite => &self.staticHolder,
                .PerFrame => &self.dynHolders[flightId],
            };

            if (resHolder.removeTexture(texId)) |tex| {
                const descIndex = self.descMan.removeTextureDescriptor(texId, @intCast(flightId));
                try self.queues[(curFrame + rc.MAX_IN_FLIGHT) % QUEUE_COUNT].addTextureDeletion(.{ .tex = tex, .descIndex = descIndex });
            }
        }
        // Abort
        for (0..QUEUE_COUNT) |i| self.queues[i].invalidateTextureCreation(texId);

        if (rc.RESOURCE_DEBUG == true) std.debug.print("Texture Removed! (ID {}) (Frame {})\n", .{ texId.val, curFrame });
    }

    // Processing Tickets
    fn createBuffer(self: *ResourceMan, bufInf: BufInf, flightId: u8) !void {
        var buf = try self.vma.allocDefinedBuffer(bufInf);
        buf.curCount = bufInf.len;
        const activeByteSize = buf.curCount * bufInf.elementSize;

        switch (bufInf.update) {
            .Overwrite => {
                self.staticHolder.addBuffer(bufInf.id, buf);
                try self.descMan.queueBufferDescriptor(buf.gpuAddress, activeByteSize, bufInf.typ, bufInf.id, 0); // Overwrite Desc always 0
            },
            .PerFrame => {
                self.dynHolders[flightId].addBuffer(bufInf.id, buf);
                try self.descMan.queueBufferDescriptor(buf.gpuAddress, activeByteSize, bufInf.typ, bufInf.id, flightId);
            },
        }
        if (rc.RESOURCE_DEBUG == true) {
            std.debug.print("Buffer Created! (ID {}) ", .{bufInf.id.val});
            self.vma.printMemoryInfo(buf.allocation);
        }
    }

    fn createTexture(self: *ResourceMan, texInf: TexInf, flightId: u8) !void {
        const texMeta: TextureMeta = self.vma.createTextureMeta(texInf);
        const tex = try self.vma.allocDefinedTexture(texInf);

        switch (texInf.update) {
            .Overwrite => {
                self.staticHolder.addTexture(texInf.id, tex);
                try self.descMan.queueTextureDescriptor(&texMeta, tex.img, texInf.id, 0); // Overwrite Desc always 0
            },
            .PerFrame => {
                self.dynHolders[flightId].addTexture(texInf.id, tex);
                try self.descMan.queueTextureDescriptor(&texMeta, tex.img, texInf.id, flightId);
            },
        }
        if (rc.RESOURCE_DEBUG) {
            std.debug.print("Texture Created! (ID {}) ", .{texInf.id.val});
            self.vma.printMemoryInfo(tex.allocation);
        }
    }

    fn destroyBuffer(self: *ResourceMan, bufZom: *const BufferZombie) void {
        self.vma.freeBuffer(&bufZom.buf);
        self.descMan.freeDescriptorIndex(bufZom.descIndex);
    }

    fn destroyTexture(self: *ResourceMan, texZom: *const TextureZombie) void {
        self.vma.freeTexture(&texZom.tex);
        self.descMan.freeDescriptorIndex(texZom.descIndex);
    }

    pub fn getBufferMeta(self: *ResourceMan, bufId: BufId) !*BufferMeta {
        if (self.bufMetas.isKeyUsed(bufId.val) == true) return self.bufMetas.getPtrByKey(bufId.val) else return error.BufferMetaIdNotUsed;
    }

    pub fn getTextureMeta(self: *ResourceMan, texId: TexId) !*TextureMeta {
        if (self.texMetas.isKeyUsed(texId.val) == true) return self.texMetas.getPtrByKey(texId.val) else return error.TextureMetaIdNotUsed;
    }

    // inline fn getResourceIndex(self: *ResourceMan, updateTyp: vhE.UpdateType, isIndirectBuf: bool) u8 {
    //     const realIndex = switch (updateTyp) {
    //         .Overwrite => 0,
    //         .PerFrame => if (bufMeta.typ == .Indirect) flightId else bufMeta.updateSlot,
    //     };
    // }

    // inline fn getResHolder(self: *ResourceMan, flightId: u8, updateTyp: vhE.UpdateType) *ResourceHolder {
    //     return switch (updateTyp) {
    //         .Overwrite => &self.staticHolder,
    //         .PerFrame => &self.dynHolders[flightId],
    //     };
    // }
};

fn convertToByteSlice(data: anytype) ![]const u8 {
    const DataType = @TypeOf(data);
    return switch (@typeInfo(DataType)) {
        .pointer => |ptr| switch (ptr.size) {
            .one => std.mem.asBytes(data),
            .slice => std.mem.sliceAsBytes(data),
            else => return error.UnsupportedPointerType,
        },
        else => return error.ExpectedPointer,
    };
}
