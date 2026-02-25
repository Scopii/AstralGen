// const DescriptorStorage = @import("DescriptorStorage.zig").DescriptorStorage;
const TextureMeta = @import("../types/res/TextureMeta.zig").TextureMeta;
const ResourceStorage = @import("ResourceStorage.zig").ResourceStorage;
const FixedList = @import("../../structures/FixedList.zig").FixedList;
const LinkedMap = @import("../../structures/LinkedMap.zig").LinkedMap;
const ArrayList = @import("../../structures/ArrayList.zig").ArrayList;
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

pub const ResourceMan = struct {
    vma: Vma,
    alloc: Allocator,
    descHeap: Buffer,
    descStride: u64,
    startOffset: u64,
    driverReservedSize: u64,

    resStorages: [rc.MAX_IN_FLIGHT]ResourceStorage,
    bufMetas: LinkedMap(BufferMeta, rc.BUF_MAX, u32, rc.BUF_MAX, 0) = .{},
    texMetas: LinkedMap(TextureMeta, rc.TEX_MAX, u32, rc.TEX_MAX, 0) = .{},

    pub fn init(alloc: Allocator, context: *const Context) !ResourceMan {
        const vma = try Vma.init(context.instance, context.gpi, context.gpu);

        var resStorages: [rc.MAX_IN_FLIGHT]ResourceStorage = undefined;
        for (0..rc.MAX_IN_FLIGHT) |i| {
            const flight: u32 = @intCast(i);
            resStorages[i] = try ResourceStorage.init(alloc, &vma, flight * rc.RESOURCE_MAX);
        }

        const heapProps = getDescriptorHeapProperties(context.gpu);
        const driverReservedSize = heapProps.minResourceHeapReservedRange;

        const alignment = heapProps.resourceHeapAlignment;
        const startOffset = (driverReservedSize + (alignment - 1)) & ~(alignment - 1);

        const descStride = @max(heapProps.bufferDescriptorSize, heapProps.imageDescriptorSize);
        const heapSize = rc.MAX_IN_FLIGHT * descStride * (rc.RESOURCE_MAX);

        return .{
            .vma = vma,
            .alloc = alloc,
            .descHeap = try vma.allocDescriptorHeap(startOffset + heapSize),
            .driverReservedSize = driverReservedSize,
            .descStride = descStride,
            .startOffset = startOffset,
            .resStorages = resStorages,
        };
    }

    pub fn deinit(self: *ResourceMan) void {
        for (0..rc.MAX_IN_FLIGHT) |i| self.resStorages[i].deinit(&self.vma);
        self.vma.freeBufferRaw(self.descHeap.handle, self.descHeap.allocation);
        self.vma.deinit();
    }

    pub fn update(self: *ResourceMan, flightId: u8, curFrame: u64) !void {
        if (rc.GPU_READBACK == true) try self.printReadbackBuffer(rc.readbackSB.id, vhT.ReadbackData, flightId);

        try self.resStorages[flightId].updateDescriptors(self.vma.gpi, flightId);

        if (curFrame < rc.MAX_IN_FLIGHT) return; // Only clean up resources queued MAX_IN_FLIGHT ago (safety check for startup)
        const start = if (rc.RESOURCE_DEBUG == true) std.time.microTimestamp() else 0;

        const bufCount = self.resStorages[flightId].cleanupBuffers(self.vma);
        const texCount = self.resStorages[flightId].cleanupTextures(self.vma);

        if (rc.RESOURCE_DEBUG == true and bufCount + texCount > 0) {
            const time = @as(f64, @floatFromInt(std.time.microTimestamp() - start)) / 1_000.0;
            std.debug.print("Destroyed Buffers ({}) Textures ({}) (in Frame {}) (FlightId {}) {d:.3} ms\n", .{ bufCount, texCount, curFrame, flightId, time });
        }
    }

    pub fn getBufferDescriptor(self: *ResourceMan, bufId: BufferMeta.BufId, flightId: u8) !u32 {
        const buffer = try self.getBuffer(bufId, flightId);
        return buffer.descIndex;
    }

    pub fn getTextureDescriptor(self: *ResourceMan, texId: TextureMeta.TexId, flightId: u8) !u32 {
        const tex = try self.getTexture(texId, flightId);
        return tex.descIndex;
    }

    pub fn resetTransfers(self: *ResourceMan, flightId: u8) void {
        self.resStorages[flightId].resetTransfers();
    }

    pub fn getTexture(self: *ResourceMan, texId: TextureMeta.TexId, flightId: u8) !*Texture {
        const texMeta = try self.getTextureMeta(texId);
        const realIndex = switch (texMeta.update) {
            .Overwrite => 0,
            .PerFrame => flightId,
        };
        return try self.resStorages[realIndex].getTexture(texId);
    }

    pub fn getBuffer(self: *ResourceMan, bufId: BufferMeta.BufId, flightId: u8) !*Buffer {
        const bufMeta = try self.getBufferMeta(bufId);
        const realIndex = switch (bufMeta.update) {
            .Overwrite => 0,
            .PerFrame => if (bufMeta.typ == .Indirect) flightId else bufMeta.updateId, // Indirect written by GPU so always current flightId.
        };
        return try self.resStorages[realIndex].getBuffer(bufId);
    }

    pub fn getTextureMeta(self: *ResourceMan, texId: TextureMeta.TexId) !*TextureMeta {
        if (self.texMetas.isKeyUsed(texId.val) == true) return self.texMetas.getPtrByKey(texId.val) else return error.TextureIdNotUsed;
    }

    pub fn getBufferMeta(self: *ResourceMan, bufId: BufferMeta.BufId) !*BufferMeta {
        if (self.bufMetas.isKeyUsed(bufId.val) == true) return self.bufMetas.getPtrByKey(bufId.val) else return error.BufferIdNotUsed;
    }

    pub fn createBuffer(self: *ResourceMan, bufInf: BufferMeta.BufInf) !void {
        for (0..bufInf.update.getCount()) |i| {
            var buf = try self.vma.allocDefinedBuffer(bufInf);
            buf.descIndex = try self.resStorages[i].getFreeDescriptorIndex();
            try self.resStorages[i].queueBufferDescriptor(buf.gpuAddress, buf.size, bufInf.typ, self.createHostAddressRange(buf.descIndex));
            self.resStorages[i].addBuffer(bufInf.id, buf);

            std.debug.print("Buffer created! (ID {}) (FlightId {}) ({}) ({}) (Descriptor {}) ", .{ bufInf.id.val, i, bufInf.typ, bufInf.update, buf.descIndex });
            self.vma.printMemoryInfo(buf.allocation);
        }
        self.bufMetas.upsert(bufInf.id.val, self.vma.createBufferMeta(bufInf));
    }

    pub fn createTexture(self: *ResourceMan, texInf: TextureMeta.TexInf) !void {
        var texMeta: TextureMeta = self.vma.createTextureMeta(texInf);

        for (0..texInf.update.getCount()) |i| {
            var tex = try self.vma.allocDefinedTexture(texInf);
            tex.descIndex = try self.resStorages[i].getFreeDescriptorIndex();
            try self.resStorages[i].queueTextureDescriptor(&texMeta, tex.img, self.createHostAddressRange(tex.descIndex));
            self.resStorages[i].addTexture(texInf.id, tex);

            std.debug.print("Texture created! (ID {}) (FlightId {}) ({}) ({}) (Descriptor {}) ", .{ texInf.id.val, i, texInf.typ, texInf.update, tex.descIndex });
            self.vma.printMemoryInfo(tex.allocation);
        }
        self.texMetas.upsert(texInf.id.val, texMeta);
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

    pub fn updateBuffer(self: *ResourceMan, bufInf: BufferMeta.BufInf, data: anytype, flightId: u8) !void {
        const bytes = try convertToByteSlice(data);
        const bufMeta = try self.getBufferMeta(bufInf.id);

        const realFlightId = switch (bufMeta.update) {
            .Overwrite => 0,
            .PerFrame => flightId,
        };

        var targetStorage = &self.resStorages[realFlightId];
        var buf = try targetStorage.getBuffer(bufInf.id);

        switch (bufInf.resize) {
            .Block => {
                if (bytes.len > buf.size) {
                    std.debug.print("Buffer Update cant fit BufId {}\n", .{bufInf.id});
                    return error.BufferBaseTooSmallForUpdate;
                }
            },
            .Grow, .Fit => {
                if ((bufInf.resize == .Fit and bytes.len != buf.size) or
                    (bufInf.resize == .Grow and bytes.len > buf.size))
                {
                    var newInf = bufInf;
                    newInf.len = @intCast((bytes.len + bufInf.elementSize - 1) / bufInf.elementSize);

                    var newBuf = try self.vma.allocDefinedBuffer(newInf);
                    newBuf.descIndex = buf.descIndex;

                    std.debug.print("Buffer resized! (ID {}) (Container {}) ({}) ({}) (Descriptor {}) ", .{ newInf.id.val, realFlightId, newInf.typ, newInf.update, newBuf.descIndex });
                    std.debug.print("Length {} ({} Bytes) -> Length {} ({} Bytes) ", .{ bufInf.len, buf.size, newInf.len, newBuf.size });
                    self.vma.printMemoryInfo(newBuf.allocation);

                    buf.descIndex = std.math.maxInt(u32);
                    try targetStorage.queueBufferKill(newInf.id);
                    targetStorage.addBuffer(newInf.id, newBuf);
                    self.bufMetas.upsert(newInf.id.val, self.vma.createBufferMeta(newInf));

                    buf = try targetStorage.getBuffer(bufInf.id); // Refresh
                }
            },
        }

        switch (bufInf.mem) {
            .Gpu => {
                try targetStorage.stageBufferUpdate(bufInf.id, bytes);
            },
            .CpuWrite => {
                const pMappedData = buf.mappedPtr orelse return error.BufferNotMapped;
                const destPtr: [*]u8 = @ptrCast(pMappedData);
                @memcpy(destPtr[0..bytes.len], bytes);
            },
            .CpuRead => return error.CpuReadBufferCantUpdate,
        }

        const newCount: u32 = @intCast(bytes.len / bufInf.elementSize);
        if (buf.curCount != newCount) {
            buf.curCount = newCount;
            try self.resStorages[flightId].queueBufferDescriptor(buf.gpuAddress, bytes.len, bufMeta.typ, self.createHostAddressRange(buf.descIndex));
            if (rc.DESCRIPTOR_DEBUG == true) std.debug.print("Descriptor update queued! (Index {}) (Buffer ID {})\n", .{ buf.descIndex, bufInf.id.val });
        }

        switch (bufMeta.update) {
            .Overwrite => {}, // Always references flightId 0
            .PerFrame => bufMeta.updateId = flightId,
        }
    }

    pub fn queueTextureKills(self: *ResourceMan, texId: TextureMeta.TexId) !void {
        const texMeta = try self.getTextureMeta(texId);
        for (0..texMeta.update.getCount()) |i| try self.resStorages[i].queueTextureKill(texId);
        self.texMetas.remove(texId.val);
    }

    pub fn queueBufferKills(self: *ResourceMan, bufId: BufferMeta.BufId) !void {
        const bufMeta = try self.getBufferMeta(bufId);
        for (0..bufMeta.update.getCount()) |i| try self.resStorages[i].queueBufferKill(bufId);
        self.bufMetas.remove(bufId.val);
    }

    fn createHostAddressRange(self: *ResourceMan, descIndex: u32) vk.VkHostAddressRangeEXT {
        const finalOffset = self.startOffset + (descIndex * self.descStride);
        const mappedData = @as([*]u8, @ptrCast(self.descHeap.mappedPtr));

        return vk.VkHostAddressRangeEXT{
            .address = mappedData + finalOffset,
            .size = self.descStride,
        };
    }
};

fn getDescriptorHeapProperties(gpu: vk.VkPhysicalDevice) vk.VkPhysicalDeviceDescriptorHeapPropertiesEXT {
    var heapProps = vk.VkPhysicalDeviceDescriptorHeapPropertiesEXT{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DESCRIPTOR_HEAP_PROPERTIES_EXT };
    var physDevProps = vk.VkPhysicalDeviceProperties2{ .sType = vk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &heapProps };
    vk.vkGetPhysicalDeviceProperties2(gpu, &physDevProps);
    return heapProps;
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
