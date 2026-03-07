const ResourceRegistry = @import("ResourceRegistry.zig").ResourceRegistry;
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
    updater: ResourceUpdater,
    registry: ResourceRegistry,
    queues: [QUEUE_COUNT]ResourceQueue,
    // bufUpdateSlots: LinkedMap(u8, rc.RESOURCE_MAX, u32, rc.RESOURCE_MAX, 0) = .{},
    // texUpdateSlots: LinkedMap(u8, rc.RESOURCE_MAX, u32, rc.RESOURCE_MAX, 0) = .{},

    pub fn init(alloc: Allocator, context: *const Context) !ResourceMan {
        const vma = try Vma.init(context.instance, context.gpi, context.gpu);
        var queues: [QUEUE_COUNT]ResourceQueue = undefined;
        for (0..QUEUE_COUNT) |i| queues[i] = .{};

        return .{
            .vma = vma,
            .alloc = alloc,
            .queues = queues,
            .registry = ResourceRegistry.init(),
            .updater = try ResourceUpdater.init(&vma),
            .descMan = try DescriptorMan.init(&vma, context.gpu),
        };
    }

    pub fn deinit(self: *ResourceMan) void {
        for (&self.queues) |*queue| {
            _ = self.destroyBuffers(queue);
            _ = self.destroyTextures(queue);
        }
        self.updater.deinit(&self.vma);
        self.registry.deinit(&self.vma);
        self.descMan.deinit(&self.vma);
        self.vma.deinit();
    }

    fn destroyBuffers(self: *ResourceMan, queue: *ResourceQueue) u64 {
        const bufDeletions = queue.getBufferDeletions();
        for (bufDeletions) |*bufZom| {
            self.vma.freeBuffer(&bufZom.buf);
            if (bufZom.buf.descIndex) |descIndex| self.descMan.freeDescriptorIndex(descIndex);
        }
        queue.clearBufferDeletions();
        return bufDeletions.len;
    }

    fn destroyTextures(self: *ResourceMan, queue: *ResourceQueue) u64 {
        const texDeletions = queue.getTextureDeletions();
        for (texDeletions) |*texZom| {
            self.vma.freeTexture(&texZom.tex);
            if (texZom.tex.descIndex) |descIndex| self.descMan.freeDescriptorIndex(descIndex);
        }
        queue.clearTextureDeletions();
        return texDeletions.len;
    }

    fn createBuffers(self: *ResourceMan, queue: *ResourceQueue, flightId: u8) !u64 {
        const bufCreations = queue.getBufferCreations();
        for (bufCreations) |bufInf| {
            var buf = try self.vma.allocDefinedBuffer(bufInf);
            buf.curCount = bufInf.len;
            const activeByteSize = buf.curCount * bufInf.elementSize;

            const bufPtr = self.registry.addBuffer(bufInf.id, buf, bufInf.update, flightId);
            try self.descMan.queueBufferDescriptor(buf.gpuAddress, activeByteSize, bufInf.typ, bufPtr);

            if (rc.RESOURCE_DEBUG == true) {
                std.debug.print("Buffer Created! (ID {}) ", .{bufInf.id.val});
                self.vma.printMemoryInfo(buf.allocation);
            }
        }
        queue.clearBufferCreations();
        return bufCreations.len;
    }

    fn createTextures(self: *ResourceMan, queue: *ResourceQueue, flightId: u8) !u64 {
        const texCreations = queue.getTextureCreations();
        for (texCreations) |texInf| {
            const texMeta = self.vma.createTextureMeta(texInf);
            const tex = try self.vma.allocDefinedTexture(texInf);

            const texPtr = self.registry.addTexture(texInf.id, tex, texInf.update, flightId);
            try self.descMan.queueTextureDescriptor(&texMeta, texPtr);

            if (rc.RESOURCE_DEBUG) {
                std.debug.print("Texture Created! (ID {}) ", .{texInf.id.val});
                self.vma.printMemoryInfo(tex.allocation);
            }
        }
        queue.clearTextureCreations();
        return texCreations.len;
    }

    pub fn update(self: *ResourceMan, flightId: u8, curFrame: u64) !void {
        const start = if (rc.RESOURCE_DEBUG == true) std.time.microTimestamp() else 0;
        if (rc.GPU_READBACK == true) try self.printReadbackBuffer(rc.readbackSB.id, vhT.ReadbackData, flightId);

        const curQueue = &self.queues[curFrame % QUEUE_COUNT];
        const bufDel = self.destroyBuffers(curQueue);
        const texDel = self.destroyTextures(curQueue);
        const bufCr = try self.createBuffers(curQueue, flightId);
        const texCr = try self.createTextures(curQueue, flightId);

        if (rc.RESOURCE_DEBUG == true and bufDel + texDel + bufCr + texCr > 0) {
            const time = @as(f64, @floatFromInt(std.time.microTimestamp() - start)) / 1_000.0;
            std.debug.print("ResMan Updated (Buf -{}) (Tex -{}) (Buf +{}) (Tex +{}) (Frame {}) (Flight {}) {d:.3} ms\n", .{ bufDel, texDel, bufCr, texCr, curFrame, flightId, time });
        }
        try self.descMan.updateDescriptors(self.vma.gpi, flightId);
    }

    // Getters
    pub fn getBufferDescriptor(self: *ResourceMan, bufId: BufId, flightId: u8) !u32 {
        const bufMeta = try self.registry.getBufferMeta(bufId);
        const buf = try self.registry.getBuffer(bufId, bufMeta.update, flightId, bufMeta.updateSlot);
        return buf.descIndex orelse error.BufferHasNoDesccriptor;
    }

    pub fn getTextureDescriptor(self: *ResourceMan, texId: TexId, flightId: u8) !u32 {
        const texMeta = try self.registry.getTextureMeta(texId);
        const tex = try self.registry.getTexture(texId, texMeta.update, flightId, texMeta.updateSlot);
        return tex.descIndex orelse error.TextureHasNoDesccriptor;
    }

    pub fn getBufferMeta(self: *ResourceMan, bufId: BufId) !*BufferMeta {
        return try self.registry.getBufferMeta(bufId);
    }

    pub fn getTextureMeta(self: *ResourceMan, texId: TexId) !*TextureMeta {
        return try self.registry.getTextureMeta(texId);
    }

    pub fn getBuffer(self: *ResourceMan, bufId: BufId, flightId: u8) !*Buffer {
        const bufMeta = try self.registry.getBufferMeta(bufId);
        return try self.registry.getBuffer(bufId, bufMeta.update, flightId, bufMeta.updateSlot);
    }

    pub fn getTexture(self: *ResourceMan, texId: TexId, flightId: u8) !*Texture {
        const texMeta = try self.registry.getTextureMeta(texId);
        return try self.registry.getTexture(texId, texMeta.update, flightId, texMeta.updateSlot);
    }

    // Adding Tickets
    pub fn addBufferResource(self: *ResourceMan, bufInf: BufInf, curFrame: u64, flightId: u8, data: anytype) !void {
        self.registry.addBufferMeta(bufInf.id, self.vma.createBufferMeta(bufInf));
        for (0..bufInf.update.getCount()) |i| {
            self.queues[(curFrame + i) % QUEUE_COUNT].addBufferCreation(bufInf);
        }
        if (data != null) try self.updateBufferResource(bufInf.id, curFrame, flightId, data);
        if (rc.RESOURCE_DEBUG == true) std.debug.print("Buffer added! (ID {}) (Frame {}) ({}) ({})\n", .{ bufInf.id.val, curFrame, bufInf.typ, bufInf.update });
    }

    pub fn addTextureResource(self: *ResourceMan, texInf: TexInf, curFrame: u64) void {
        self.registry.addTextureMeta(texInf.id, self.vma.createTextureMeta(texInf));
        for (0..texInf.update.getCount()) |i| {
            self.queues[(curFrame + i) % QUEUE_COUNT].addTextureCreation(texInf);
        }
        if (rc.RESOURCE_DEBUG == true) std.debug.print("Texture added! (ID {}) (Frame {}) ({}) ({})\n", .{ texInf.id.val, curFrame, texInf.typ, texInf.update });
    }

    pub fn removeBufferResource(self: *ResourceMan, bufId: BufId, curFrame: u64) !void {
        const bufMeta = try self.registry.getBufferMeta(bufId);

        for (0..bufMeta.update.getCount()) |flightId| { // Kill
            if (self.registry.removeBuffer(bufId, bufMeta.update, @intCast(flightId))) |buf| {
                try self.queues[(curFrame + rc.MAX_IN_FLIGHT) % QUEUE_COUNT].addBufferDeletion(.{ .buf = buf });
            }
        }
        for (0..QUEUE_COUNT) |i| self.queues[i].invalidateBufferCreation(bufId); // Abort

        self.registry.removeBufferMeta(bufId);

        if (rc.RESOURCE_DEBUG == true) std.debug.print("Buffer Removed! (ID {}) (Frame {})\n", .{ bufId.val, curFrame });
    }

    pub fn removeTextureResource(self: *ResourceMan, texId: TexId, curFrame: u64) !void {
        const texMeta = try self.registry.getTextureMeta(texId);

        for (0..texMeta.update.getCount()) |flightId| { // Kill
            if (self.registry.removeTexture(texId, texMeta.update, @intCast(flightId))) |tex| {
                try self.queues[(curFrame + rc.MAX_IN_FLIGHT) % QUEUE_COUNT].addTextureDeletion(.{ .tex = tex });
            }
        }
        for (0..QUEUE_COUNT) |i| self.queues[i].invalidateTextureCreation(texId); // Abort

        self.registry.removeTextureMeta(texId);

        if (rc.RESOURCE_DEBUG == true) std.debug.print("Texture Removed! (ID {}) (Frame {})\n", .{ texId.val, curFrame });
    }

    pub fn updateBufferResource(self: *ResourceMan, bufId: BufId, curFrame: u64, flightId: u8, data: anytype) !void {
        const bufMeta = try self.registry.getBufferMeta(bufId);
        const bytes = try convertToByteSlice(data);
        const newCount: u32 = @intCast(bytes.len / bufMeta.elementSize);

        switch (bufMeta.update) {
            .Rarely => try self.updateStaticBuffer(bufId, bufMeta, bytes, newCount, curFrame, flightId),
            .PerFrame, .Often => try self.updateDynamicBuffer(bufId, bufMeta, bytes, newCount, curFrame, flightId),
        }
    }

    fn updateDynamicBuffer(self: *ResourceMan, bufId: BufId, meta: *BufferMeta, bytes: []const u8, newCount: u32, curFrame: u64, flightId: u8) !void {
        if (meta.update == .Often) meta.updateSlot = (meta.updateSlot + 1) % meta.update.getCount();

        if (self.registry.checkBuffer(bufId, meta.update, flightId, meta.updateSlot)) |buf| {
            const needsRealloc = try checkResize(meta.resize, bytes.len, buf.size);

            if (needsRealloc) {
                const newInf = BufInf{ .id = bufId, .mem = meta.mem, .elementSize = meta.elementSize, .len = newCount, .typ = meta.typ, .update = meta.update, .resize = meta.resize };
                try self.removeBufferResource(bufId, curFrame);
                try self.addBufferResource(newInf, curFrame, flightId, null);
                return;
            } else if (buf.curCount != newCount) {
                try self.descMan.queueBufferDescriptor(buf.gpuAddress, bytes.len, meta.typ, buf);
                buf.curCount = newCount;
            }
        }

        for (0..QUEUE_COUNT) |i| {
            if (self.queues[i].checkBufferCreation(bufId)) |bufInf| {
                const newByteSize = newCount * meta.elementSize;
                const ticketByteSize = bufInf.len * meta.elementSize;
                if (try checkResize(meta.resize, newByteSize, ticketByteSize)) bufInf.len = newCount;
            }
        }
        try self.updater.stageBufferUpdate(bufId, bytes, meta.updateSlot, flightId);
    }

    fn updateStaticBuffer(self: *ResourceMan, bufId: BufId, meta: *BufferMeta, bytes: []const u8, newCount: u32, curFrame: u64, flightId: u8) !void {
        if (self.registry.checkBuffer(bufId, .Rarely, 0, 0)) |oldBuf| { // 0,0 — flightId irrelevant for .Rarely
            const needsRealloc = try checkResize(meta.resize, bytes.len, oldBuf.size);

            if (!needsRealloc) {
                // All three resize modes agree: fits in place
                if (oldBuf.curCount != newCount) {
                    try self.descMan.queueBufferDescriptor(oldBuf.gpuAddress, bytes.len, meta.typ, oldBuf);
                    oldBuf.curCount = newCount;
                }
                try self.updater.stageBufferUpdate(bufId, bytes, 0, flightId);
                return;
            }
        }
        // Realloc path — buffer missing OR too small/wrong size
        if (self.registry.removeBuffer(bufId, .Rarely, 0)) |oldBuf| {
            try self.queues[(curFrame + rc.MAX_IN_FLIGHT) % QUEUE_COUNT].addBufferDeletion(.{ .buf = oldBuf });
        }
        for (0..QUEUE_COUNT) |i| self.queues[i].invalidateBufferCreation(bufId);

        const newInf = BufInf{ .id = bufId, .mem = meta.mem, .elementSize = meta.elementSize, .len = newCount, .typ = meta.typ, .update = meta.update, .resize = meta.resize };
        var newBuf = try self.vma.allocDefinedBuffer(newInf);
        newBuf.curCount = newCount;
        const newBufPtr = self.registry.addBuffer(bufId, newBuf, .Rarely, 0); // 0 — .Rarely always slot 0
        try self.descMan.queueBufferDescriptor(newBuf.gpuAddress, bytes.len, meta.typ, newBufPtr);
        try self.updater.stageBufferUpdate(bufId, bytes, 0, flightId);
    }

    pub fn resizeTextureResource(self: *ResourceMan, id: TexId, newWidth: u32, newHeight: u32, curFrame: u64, _: u8) !void { // flightId now unused?
        const meta = try self.registry.getTextureMeta(id);
        var needsRemove = false;

        for (0..meta.update.getCount()) |flightId| { // Check all alive sub-resources
            if (self.registry.checkTexture(id, meta.update, @intCast(flightId), meta.updateSlot)) |tex| {
                if (tex.extent.width != newWidth or tex.extent.height != newHeight) {
                    needsRemove = true;
                    break;
                }
            }
        }

        if (needsRemove) {
            const newInf = TexInf{ .id = id, .mem = meta.mem, .typ = meta.texType, .width = newWidth, .height = newHeight, .depth = 1, .update = meta.update, .resize = meta.resize };
            try self.removeTextureResource(id, curFrame); // kills alive + aborts tickets
            self.addTextureResource(newInf, curFrame); // re-queues all
            return;
        }

        for (0..QUEUE_COUNT) |i| { // Update any still-unborn tickets regardless
            if (self.queues[i].checkTextureCreation(id)) |texInf| {
                texInf.width = newWidth;
                texInf.height = newHeight;
            }
        }
    }

    // pub fn updateTextureResource(_: *ResourceMan2, _: TexId) void {} // Not needed yet

    fn getBufferDataPtr(self: *ResourceMan, bufId: BufferMeta.BufId, comptime T: type, flightId: u8) !*T {
        const buf = try self.getBuffer(bufId, flightId);
        if (buf.mappedPtr) |ptr| {
            return @as(*T, @ptrCast(@alignCast(ptr)));
        }
        return error.BufferNotHostVisible;
    }

    fn printReadbackBuffer(self: *ResourceMan, bufId: BufferMeta.BufId, comptime T: type, flightId: u8) !void {
        const readbackPtr = try self.getBufferDataPtr(bufId, T, flightId);
        std.debug.print("Readback: {}\n", .{readbackPtr.*});
    }
};

fn checkResize(resize: vhE.ResizeType, newSize: u64, oldSize: u64) !bool {
    return switch (resize) {
        .Block => if (newSize > oldSize) error.BufferBaseTooSmallForUpdate else false,
        .Grow => newSize > oldSize,
        .Fit => newSize != oldSize,
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
