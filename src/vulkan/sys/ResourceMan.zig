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
        const realDescId = getRealFlightId(bufMeta.update, flightId, bufMeta.updateSlot);
        return try self.descMan.getBufferDescriptor(bufId, realDescId);
    }

    pub fn getTextureDescriptor(self: *ResourceMan, texId: TexId, flightId: u8) !u32 {
        const texMeta = try self.getTextureMeta(texId);
        const realDescId = getRealFlightId(texMeta.update, flightId, texMeta.updateSlot);
        return try self.descMan.getTextureDescriptor(texId, realDescId);
    }

    pub fn getBuffer(self: *ResourceMan, bufId: BufId, flightId: u8) !*Buffer {
        const bufMeta = try self.getBufferMeta(bufId);
        const resHolder = self.getResHolder(bufMeta.update, flightId, bufMeta.updateSlot);
        return try resHolder.getBuffer(bufId);
    }

    pub fn getTexture(self: *ResourceMan, texId: TexId, flightId: u8) !*Texture {
        const texMeta = try self.getTextureMeta(texId);
        const resHolder = self.getResHolder(texMeta.update, flightId, texMeta.updateSlot);
        return try resHolder.getTexture(texId);
    }

    // Adding Tickets
    pub fn addBufferResource(self: *ResourceMan, bufInf: BufInf, curFrame: u64, flightId: u8, data: anytype) !void {
        self.bufMetas.upsert(bufInf.id.val, self.vma.createBufferMeta(bufInf));
        for (0..bufInf.update.getCount()) |i| {
            self.queues[(curFrame + i) % QUEUE_COUNT].addBufferCreation(bufInf);
        }
        if (data != null) try self.updateBufferResource(bufInf.id, curFrame, flightId, data);
        if (rc.RESOURCE_DEBUG == true) std.debug.print("Buffer added! (ID {}) (Frame {}) ({}) ({})\n", .{ bufInf.id.val, curFrame, bufInf.typ, bufInf.update });
    }

    pub fn addTextureResource(self: *ResourceMan, texInf: TexInf, curFrame: u64) void {
        self.texMetas.upsert(texInf.id.val, self.vma.createTextureMeta(texInf));
        for (0..texInf.update.getCount()) |i| {
            self.queues[(curFrame + i) % QUEUE_COUNT].addTextureCreation(texInf);
        }
        if (rc.RESOURCE_DEBUG == true) std.debug.print("Texture added! (ID {}) (Frame {}) ({}) ({})\n", .{ texInf.id.val, curFrame, texInf.typ, texInf.update });
    }

    pub fn updateBufferResource(self: *ResourceMan, bufId: BufId, curFrame: u64, flightId: u8, data: anytype) !void {
        const bufMeta = try self.getBufferMeta(bufId);
        const bytes = try convertToByteSlice(data);
        const newCount: u32 = @intCast(bytes.len / bufMeta.elementSize);

        switch (bufMeta.update) {
            .Recreation => try self.updateOverwriteBuffer(bufId, bufMeta, bytes, newCount, curFrame, flightId),
            .PerFrame, .OnDemand => try self.updateDynBuffer(bufId, bufMeta, bytes, newCount, curFrame, flightId),
        }
    }

    fn updateOverwriteBuffer(self: *ResourceMan, bufId: BufId, bufMeta: *BufferMeta, bytes: []const u8, newCount: u32, curFrame: u64, flightId: u8) !void {
        if (self.staticHolder.buffers.isKeyUsed(bufId.val)) {
            const oldBuf = try self.staticHolder.getBuffer(bufId);

            switch (bufMeta.resize) {
                .Block => {
                    if (bytes.len > oldBuf.size) return error.BufferBaseTooSmallForUpdate;
                    // fits, stage in place
                    if (oldBuf.curCount != newCount) {
                        try self.descMan.queueBufferDescriptor(oldBuf.gpuAddress, bytes.len, bufMeta.typ, bufId, 0);
                        oldBuf.curCount = newCount;
                    }
                    try self.resUpdaters[flightId].stageBufferUpdate(bufId, bytes, 0);
                    return;
                },
                .Grow => {
                    if (bytes.len <= oldBuf.size) { // fits, stage in place
                        if (oldBuf.curCount != newCount) {
                            try self.descMan.queueBufferDescriptor(oldBuf.gpuAddress, bytes.len, bufMeta.typ, bufId, 0);
                            oldBuf.curCount = newCount;
                        }
                        try self.resUpdaters[flightId].stageBufferUpdate(bufId, bytes, 0);
                        return;
                    }
                    // too big, fall through to realloc
                },
                .Fit => {}, // always realloc
            }
        }

        // Realloc path: remove old if alive, invalidate tickets, allocate fresh
        if (self.staticHolder.removeBuffer(bufId)) |oldBuf| {
            const descIndex = self.descMan.removeBufferDescriptor(bufId, 0);
            try self.queues[(curFrame + rc.MAX_IN_FLIGHT) % QUEUE_COUNT].addBufferDeletion(.{ .buf = oldBuf, .descIndex = descIndex });
        }
        for (0..QUEUE_COUNT) |i| self.queues[i].invalidateBufferCreation(bufId);

        const newInf = BufInf{ .id = bufId, .mem = bufMeta.mem, .elementSize = bufMeta.elementSize, .len = newCount, .typ = bufMeta.typ, .update = bufMeta.update, .resize = bufMeta.resize };
        var newBuf = try self.vma.allocDefinedBuffer(newInf);
        newBuf.curCount = newCount;
        self.staticHolder.addBuffer(bufId, newBuf);
        try self.descMan.queueBufferDescriptor(newBuf.gpuAddress, bytes.len, bufMeta.typ, bufId, 0);
        try self.resUpdaters[flightId].stageBufferUpdate(bufId, bytes, 0);
    }

    fn updateDynBuffer(self: *ResourceMan, bufId: BufId, bufMeta: *BufferMeta, bytes: []const u8, newCount: u32, curFrame: u64, flightId: u8) !void {
        bufMeta.updateSlot = (bufMeta.updateSlot + 1) % bufMeta.update.getCount();
        const realFlight = getRealFlightId(bufMeta.update, flightId, bufMeta.updateSlot);
        const resHolder = self.getResHolder(bufMeta.update, flightId, bufMeta.updateSlot);

        if (resHolder.buffers.isKeyUsed(bufId.val)) {
            const buf = try resHolder.getBuffer(bufId);
            const needsRealloc = try checkResize(bufMeta.resize, bytes.len, buf.size);

            if (needsRealloc) {
                const newInf = BufInf{
                    .id = bufId,
                    .mem = bufMeta.mem,
                    .elementSize = bufMeta.elementSize,
                    .len = newCount,
                    .typ = bufMeta.typ,
                    .update = bufMeta.update,
                    .resize = bufMeta.resize,
                };
                try self.removeBufferResource(bufId, curFrame);
                try self.addBufferResource(newInf, curFrame, flightId, null);
                return;
            } else if (buf.curCount != newCount) {
                const newByteSize = newCount * bufMeta.elementSize;
                try self.descMan.queueBufferDescriptor(buf.gpuAddress, newByteSize, bufMeta.typ, bufId, realFlight);
                buf.curCount = newCount;
            }
        }

        for (0..QUEUE_COUNT) |i| {
            if (self.queues[i].checkBufferCreation(bufId)) |bufInf| {
                if (try checkResize(bufMeta.resize, newCount, bufInf.len) == true) bufInf.len = newCount;
            }
        }
        try self.resUpdaters[flightId].stageBufferUpdate(bufId, bytes, bufMeta.updateSlot);
    }

    pub fn resizeTextureResource(self: *ResourceMan, texId: TexId, newWidth: u32, newHeight: u32, curFrame: u64, _: u8) !void { // flightId now unused?
        const texMeta = try self.getTextureMeta(texId);
        var needsRemove = false;

        for (0..texMeta.update.getCount()) |i| { // Check all alive sub-resources
            const fi: u8 = @intCast(i);
            const resHolder = switch (texMeta.update) {
                .Recreation => &self.staticHolder,
                .PerFrame, .OnDemand => &self.dynHolders[fi],
            };
            if (resHolder.textures.isKeyUsed(texId.val)) {
                const tex = try resHolder.getTexture(texId);
                if (tex.extent.width != newWidth or tex.extent.height != newHeight) {
                    needsRemove = true;
                    break;
                }
            }
        }

        if (needsRemove) {
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
            try self.removeTextureResource(texId, curFrame); // kills alive + aborts tickets
            self.addTextureResource(newInf, curFrame); // re-queues all
            return;
        }

        for (0..QUEUE_COUNT) |i| { // Update any still-unborn tickets regardless
            if (self.queues[i].checkTextureCreation(texId)) |texInf| {
                texInf.width = newWidth;
                texInf.height = newHeight;
            }
        }
    }

    // pub fn updateTextureResource(_: *ResourceMan2, _: TexId) void {} // Not needed yet

    pub fn removeBufferResource(self: *ResourceMan, bufId: BufId, curFrame: u64) !void {
        const bufMeta = try self.getBufferMeta(bufId);

        for (0..bufMeta.update.getCount()) |flightId| { // Kill
            const resHolder = switch (bufMeta.update) {
                .Recreation => &self.staticHolder,
                .OnDemand, .PerFrame => &self.dynHolders[flightId],
            };
            if (resHolder.removeBuffer(bufId)) |buf| {
                const descIndex = self.descMan.removeBufferDescriptor(bufId, @intCast(flightId));
                try self.queues[(curFrame + rc.MAX_IN_FLIGHT) % QUEUE_COUNT].addBufferDeletion(.{ .buf = buf, .descIndex = descIndex });
            }
        }
        for (0..QUEUE_COUNT) |i| self.queues[i].invalidateBufferCreation(bufId); // Abort

        if (rc.RESOURCE_DEBUG == true) std.debug.print("Buffer Removed! (ID {}) (Frame {})\n", .{ bufId.val, curFrame });
    }

    pub fn removeTextureResource(self: *ResourceMan, texId: TexId, curFrame: u64) !void {
        const texMeta = try self.getTextureMeta(texId);

        for (0..texMeta.update.getCount()) |flightId| { // Kill
            const resHolder = switch (texMeta.update) {
                .Recreation => &self.staticHolder,
                .OnDemand, .PerFrame => &self.dynHolders[flightId],
            };
            if (resHolder.removeTexture(texId)) |tex| {
                const descIndex = self.descMan.removeTextureDescriptor(texId, @intCast(flightId));
                try self.queues[(curFrame + rc.MAX_IN_FLIGHT) % QUEUE_COUNT].addTextureDeletion(.{ .tex = tex, .descIndex = descIndex });
            }
        }
        for (0..QUEUE_COUNT) |i| self.queues[i].invalidateTextureCreation(texId); // Abort

        if (rc.RESOURCE_DEBUG == true) std.debug.print("Texture Removed! (ID {}) (Frame {})\n", .{ texId.val, curFrame });
    }

    // Processing Tickets
    fn createBuffer(self: *ResourceMan, bufInf: BufInf, flightId: u8) !void {
        var buf = try self.vma.allocDefinedBuffer(bufInf);
        buf.curCount = bufInf.len;
        const activeByteSize = buf.curCount * bufInf.elementSize;

        switch (bufInf.update) {
            .Recreation => {
                self.staticHolder.addBuffer(bufInf.id, buf);
                try self.descMan.queueBufferDescriptor(buf.gpuAddress, activeByteSize, bufInf.typ, bufInf.id, 0); // Overwrite Desc always 0
            },
            .OnDemand, .PerFrame => {
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
            .Recreation => {
                self.staticHolder.addTexture(texInf.id, tex);
                try self.descMan.queueTextureDescriptor(&texMeta, tex.img, texInf.id, 0); // Overwrite Desc always 0
            },
            .OnDemand, .PerFrame => {
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

    // Helpers

    inline fn getResHolder(self: *ResourceMan, updateTyp: vhE.UpdateType, flightId: u8, updateSlot: u8) *ResourceHolder {
        return switch (updateTyp) {
            .Recreation => &self.staticHolder,
            .OnDemand => &self.dynHolders[updateSlot],
            .PerFrame => &self.dynHolders[flightId],
        };
    }
};

inline fn checkResize(resize: vhE.ResizeType, newSize: u64, oldSize: u64) !bool {
    return switch (resize) {
        .Block => if (newSize > oldSize) error.BufferBaseTooSmallForUpdate else false,
        .Grow => newSize > oldSize,
        .Fit => newSize != oldSize,
    };
}

inline fn getRealFlightId(updateTyp: vhE.UpdateType, flightId: u8, updateSlot: u8) u8 {
    return switch (updateTyp) {
        .Recreation => 0, // Overwrite Desc always 0
        .OnDemand => updateSlot,
        .PerFrame => flightId,
    };
}

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
