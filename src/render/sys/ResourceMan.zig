const ResourceRegistry = @import("ResourceRegistry.zig").ResourceRegistry;
const TextureMeta = @import("../types/res/TextureMeta.zig").TextureMeta;
const ResourceUpdater = @import("ResourceUpdater.zig").ResourceUpdater;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const BufferMeta = @import("../types/res/BufferMeta.zig").BufferMeta;
const ResourceQueue = @import("ResourceQueue.zig").ResourceQueue;
const DescriptorMan = @import("DescriptorMan.zig").DescriptorMan;
const KeyPool = @import("../../.structures/KeyPool.zig").KeyPool;
const Texture = @import("../types/res/Texture.zig").Texture;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const rc = @import("../../.configs/renderConfig.zig");
const vk = @import("../../.modules/vk.zig").c;
const Context = @import("Context.zig").Context;
const vhT = @import("../help/Types.zig");
const vhE = @import("../help/Enums.zig");
const rH = @import("ResHelpers.zig");
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

    texturePool: LinkedMap(TexId, 32, u31, 32, 0) = .{},
    teyKeyPool: KeyPool(u31, 100) = .{},

    pub fn init(alloc: Allocator, context: *const Context) !ResourceMan {
        const vma = try Vma.init(context.instance, context.gpi, context.gpu);
        var queues: [QUEUE_COUNT]ResourceQueue = undefined;
        for (0..QUEUE_COUNT) |i| queues[i] = .{};

        return .{
            .vma = vma,
            .alloc = alloc,
            .queues = queues,
            .registry = ResourceRegistry.init(),
            .updater = try ResourceUpdater.init(alloc, &vma),
            .descMan = try DescriptorMan.init(&vma, context.gpu),
        };
    }

    pub fn deinit(self: *ResourceMan) void {
        for (&self.queues) |*queue| {
            _ = self.destroyResources(queue, Buffer);
            _ = self.destroyResources(queue, Texture);
        }
        self.updater.deinit(&self.vma);
        self.registry.deinit(&self.vma);
        self.descMan.deinit(&self.vma);
        self.vma.deinit();

        const key = self.teyKeyPool.reserveKey();
        self.teyKeyPool.freeKey(key);
    }

    pub const VirtualTexture = @import("../types/res/VirtualTexture.zig").VirtualTexture;

    pub fn assignTexture(self: *ResourceMan, virtualTex: VirtualTexture, curFrame: u64, flightId: u8) void {
        const texInf = TexInf{
            .id = virtualTex.id, // Should be assigned?
            .mem = virtualTex.mem,
            .typ = virtualTex.texType,
            .width = virtualTex.width,
            .height = virtualTex.height,
            .depth = virtualTex.depth,
            .update = virtualTex.update,
            .resize = virtualTex.resize,
        };
        self.addResource(texInf, curFrame, flightId, null);
        // self.texturePool.upsert(virtualTex.id, item: TexId)
        std.debug.print("Virtual Texture assigned ({s} ID {})", .{ virtualTex.name, virtualTex.id.val });
    }

    fn destroyResources(self: *ResourceMan, queue: *ResourceQueue, comptime T: type) u64 {
        const deletions = queue.getDeletions(T);
        for (deletions) |*zombie| {
            switch (T) {
                Buffer => self.vma.freeBuffer(zombie),
                Texture => self.vma.freeTexture(zombie),
                else => @compileError("destroyResources: unsupported type"),
            }
            if (zombie.descIndex) |descIndex| self.descMan.freeDescriptorIndex(descIndex);
        }
        queue.clearDeletions(T);
        return deletions.len;
    }

    fn createResources(self: *ResourceMan, queue: *ResourceQueue, comptime ResType: type, flightId: u8) !u64 {
        const creations = queue.getCreations(ResType);

        for (creations) |*inf| {
            var resPtr: *ResType = undefined;
            var res: ResType = undefined;

            switch (ResType) {
                Buffer => {
                    res = try self.vma.allocDefinedBuffer(inf);
                    res.curCount = inf.len;
                    resPtr = self.registry.add(inf.id, res, inf.update, flightId);
                    try self.descMan.queueBufferDescriptor(res.gpuAddress, res.curCount * inf.elementSize, inf.typ, resPtr);
                },
                Texture => {
                    const texMeta = self.vma.createTextureMeta(inf);
                    res = try self.vma.allocDefinedTexture(inf);
                    resPtr = self.registry.add(inf.id, res, inf.update, flightId);
                    try self.descMan.queueTextureDescriptor(&texMeta, resPtr);
                },
                else => @compileError("createResources: unsupported type"),
            }

            if (rc.RESOURCE_DEBUG == true) {
                std.debug.print("{s} (ID {}) Created! ", .{ rH.typeName(ResType), inf.id.val });
                self.vma.printMemoryInfo(resPtr.allocation);
            }
        }
        queue.clearCreations(ResType);
        return creations.len;
    }

    pub fn update(self: *ResourceMan, flightId: u8, curFrame: u64) !void {
        const start = if (rc.RESOURCE_DEBUG == true) std.time.microTimestamp() else 0;
        if (rc.GPU_READBACK == true) try self.printReadbackBuffer(rc.readbackSB.id, vhT.ReadbackData, flightId);

        const curQueue = &self.queues[curFrame % QUEUE_COUNT];
        const bufDel = self.destroyResources(curQueue, Buffer);
        const texDel = self.destroyResources(curQueue, Texture);
        const bufCr = try self.createResources(curQueue, Buffer, flightId);
        const texCr = try self.createResources(curQueue, Texture, flightId);

        if (rc.RESOURCE_DEBUG == true and bufDel + texDel + bufCr + texCr > 0) {
            const time = @as(f64, @floatFromInt(std.time.microTimestamp() - start)) / 1_000.0;
            std.debug.print("ResMan Updated (Buf -{}) (Tex -{}) (Buf +{}) (Tex +{}) (Frame {}) (Flight {}) {d:.3} ms\n", .{ bufDel, texDel, bufCr, texCr, curFrame, flightId, time });
        }
        try self.descMan.updateDescriptors(self.vma.gpi, flightId);
    }

    // Meta
    fn addMeta(self: *ResourceMan, id: anytype, meta: anytype) void {
        self.registry.addMeta(id, meta);
    }

    pub fn getMeta(self: *ResourceMan, id: anytype) !*rH.MetaOfId(@TypeOf(id)) {
        return try self.registry.getMeta(id);
    }

    fn removeMeta(self: *ResourceMan, id: anytype) void {
        self.registry.removeMeta(id);
    }

    // Getters
    pub fn getDescriptor(self: *ResourceMan, id: anytype, flightId: u8) !u32 {
        const meta = try self.getMeta(id);
        const res = try self.registry.get(id, meta.update, flightId, meta.updateSlot);
        return res.descIndex orelse error.ResIdHasNoDescriptor;
    }

    pub fn get(self: *ResourceMan, id: anytype, flightId: u8) !*rH.ResOfId(@TypeOf(id)) {
        const meta = try self.getMeta(id);
        return try self.registry.get(id, meta.update, flightId, meta.updateSlot);
    }

    // Adding Tickets
    pub fn addResource(self: *ResourceMan, inf: anytype, curFrame: u64, flightId: u8, data: anytype) !void {
        const ResType = rH.ResOfInf(@TypeOf(inf));
        const meta = switch (ResType) {
            Buffer => self.vma.createBufferMeta(&inf),
            Texture => self.vma.createTextureMeta(&inf),
            else => unreachable,
        };

        self.addMeta(inf.id, meta);
        for (0..meta.update.getCount()) |i| {
            self.queues[(curFrame + i) % QUEUE_COUNT].addCreation(inf);
        }

        if (data != null) {
            switch (ResType) {
                Buffer => try self.updateBufferResource(inf.id, curFrame, flightId, data),
                Texture => try self.updateTextureResource(inf.id, curFrame, flightId, data, null),
                else => unreachable,
            }
        }
        if (rc.RESOURCE_DEBUG == true) std.debug.print("{s} added! (ID {}) (Frame {}) ({}) ({})\n", .{ rH.typeName(ResType), inf.id.val, curFrame, inf.typ, meta.update });
    }

    pub fn removeResource(self: *ResourceMan, id: anytype, curFrame: u64) !void {
        const ResType = rH.ResOfId(@TypeOf(id));
        const meta = try self.getMeta(id);

        for (0..meta.update.getCount()) |flightId| { // Kill
            if (self.registry.remove(id, meta.update, @intCast(flightId))) |res| {
                try self.queues[(curFrame + rc.MAX_IN_FLIGHT) % QUEUE_COUNT].addDeletion(res);
            }
        }
        for (0..QUEUE_COUNT) |i| self.queues[i].invalidateCreation(id); // Abort
        self.removeMeta(id);

        if (rc.RESOURCE_DEBUG == true) std.debug.print("{s} Removed! (ID {}) (Frame {})\n", .{ rH.typeName(ResType), id.val, curFrame });
    }

    pub fn updateTextureResource(self: *ResourceMan, texId: TexId, curFrame: u64, flightId: u8, data: anytype, newExtent: ?vk.VkExtent3D) !void {
        const texMeta = try self.getMeta(texId);
        const bytes = try rH.convertToByteSlice(data);

        if (newExtent) |extent| try self.resizeTextureResource(texId, extent.width, extent.height, extent.depth, curFrame, flightId);

        switch (texMeta.update) {
            .Rarely => {},
            .PerFrame, .Often => {
                if (texMeta.update == .Often and texMeta.lastUpdateFrame != curFrame) {
                    texMeta.lastUpdateFrame = curFrame;
                    texMeta.updateSlot = (texMeta.updateSlot + 1) % texMeta.update.getCount();
                }
            },
        }

        if (self.registry.check(texId, texMeta.update, flightId, texMeta.updateSlot)) |oldTex| { // Validated because resize not included
            try self.updater.stageTextureUpdate(texId, bytes, oldTex.extent.width, oldTex.extent.height, flightId);
            return;
        }

        for (0..QUEUE_COUNT) |i| {
            if (self.queues[i].checkCreation(texId)) |texInf| {
                try self.updater.stageTextureUpdate(texId, bytes, texInf.width, texInf.height, flightId);
                break;
            }
        }
    }

    pub fn updateBufferResource(self: *ResourceMan, bufId: BufId, curFrame: u64, flightId: u8, data: anytype) !void {
        const bufMeta = try self.getMeta(bufId);
        const bytes = try rH.convertToByteSlice(data);
        const newCount: u32 = @intCast(bytes.len / bufMeta.elementSize);

        try self.resizeBufferResource(bufId, bufMeta, bytes, newCount, curFrame, flightId);

        switch (bufMeta.update) {
            .Rarely => {},
            .PerFrame, .Often => {
                if (bufMeta.update == .Often and bufMeta.lastUpdateFrame != curFrame) {
                    bufMeta.lastUpdateFrame = curFrame;
                    bufMeta.updateSlot = (bufMeta.updateSlot + 1) % bufMeta.update.getCount();
                }
            },
        }
        try self.updater.stageBufferUpdate(bufId, bytes, flightId);
    }

    fn resizeBufferResource(self: *ResourceMan, bufId: BufId, meta: *BufferMeta, bytes: []const u8, newCount: u32, curFrame: u64, flightId: u8) !void {
        if (self.registry.check(bufId, meta.update, flightId, meta.updateSlot)) |buf| {
            const needsRealloc = try rH.checkBufferResize(meta.resize, bytes.len, buf.size);

            if (needsRealloc) {
                const newInf = BufInf{ .id = bufId, .mem = meta.mem, .elementSize = meta.elementSize, .len = newCount, .typ = meta.typ, .update = meta.update, .resize = meta.resize };
                try self.removeResource(bufId, curFrame);
                try self.addResource(newInf, curFrame, flightId, null);
                return;
            } else if (buf.curCount != newCount) {
                try self.descMan.queueBufferDescriptor(buf.gpuAddress, bytes.len, meta.typ, buf);
                buf.curCount = newCount;
            }
        }

        for (0..QUEUE_COUNT) |i| {
            if (self.queues[i].checkCreation(bufId)) |bufInf| {
                const newByteSize = newCount * meta.elementSize;
                const ticketByteSize = bufInf.len * meta.elementSize;
                if (try rH.checkBufferResize(meta.resize, newByteSize, ticketByteSize)) bufInf.len = newCount;
            }
        }
    }

    pub fn updateBufferResourceSegment(self: *ResourceMan, bufId: BufId, flightId: u8, data: anytype, element: u32) !void {
        const bufMeta = try self.getMeta(bufId);
        const bytes = try rH.convertToByteSlice(data);
        const elementOffset: u64 = @as(u64, bufMeta.elementSize) * element;

        const bufSize = self.getBufferSize(bufId, bufMeta.update, flightId, bufMeta.updateSlot);
        if (elementOffset + bytes.len > bufSize) return error.SegmentWriteOutOfBounds;
        try self.updater.stageBufferSegmentUpdate(bufId, bytes, flightId, elementOffset);
    }

    fn getBufferSize(self: *ResourceMan, bufId: BufId, updateTyp: vhE.UpdateType, flightId: u8, updateSlot: u8) u64 {
        if (self.registry.check(bufId, updateTyp, flightId, updateSlot)) |buf| return buf.size;
        for (0..QUEUE_COUNT) |i| {
            if (self.queues[i].checkCreation(bufId)) |inf| return @as(u64, inf.len) * inf.elementSize;
        }
        return 0;
    }

    pub fn resizeTextureResource(self: *ResourceMan, texId: TexId, newWidth: u32, newHeight: u32, newDepth: u32, curFrame: u64, flightId: u8) !void {
        const meta = try self.getMeta(texId);
        var oldWidth: u32 = 0;
        var oldHeight: u32 = 0;
        var oldDepth: u32 = 0;
        var needsRemove = false;

        for (0..meta.update.getCount()) |i| { // Check all alive sub-resources
            if (self.registry.check(texId, meta.update, @intCast(i), meta.updateSlot)) |tex| {
                if (try rH.checkTextureResize(meta.resize, tex.extent, .{ .width = newWidth, .height = newHeight, .depth = newDepth })) {
                    needsRemove = true;
                    oldWidth = tex.extent.width;
                    oldHeight = tex.extent.height;
                    oldDepth = tex.extent.depth;
                    break;
                }
            }
        }

        if (needsRemove) {
            const newInf = TexInf{ .id = texId, .mem = meta.mem, .typ = meta.texType, .width = newWidth, .height = newHeight, .depth = newDepth, .update = meta.update, .resize = meta.resize };
            try self.removeResource(texId, curFrame); // kills alive + aborts tickets
            try self.addResource(newInf, curFrame, flightId, null); // re-queues all
            std.debug.print("Texture (ID {}) resized ({}x{} to {}x{})\n", .{ texId.val, oldWidth, oldHeight, newWidth, newHeight }); // Depth missing
            return;
        }

        for (0..QUEUE_COUNT) |i| { // Update any still-unborn tickets regardless
            if (self.queues[i].checkCreation(texId)) |texInf| {
                texInf.width = newWidth;
                texInf.height = newHeight;
                texInf.depth = newDepth;
                std.debug.print("Texture (ID {}) Queue {} resized before creation to {}x{}\n", .{ texId.val, i, newWidth, newHeight }); // Depth missing
            }
        }
    }

    fn getBufferDataPtr(self: *ResourceMan, bufId: BufferMeta.BufId, comptime T: type, flightId: u8) !*T {
        const buf = try self.get(bufId, flightId);
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
