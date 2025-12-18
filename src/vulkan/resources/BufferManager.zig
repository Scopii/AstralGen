const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const vkFn = @import("../../modules/vk.zig");
const Allocator = std.mem.Allocator;
const Context = @import("../Context.zig").Context;
const GpuAllocator = @import("GpuAllocator.zig").GpuAllocator;
const check = @import("../error.zig").check;
const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;
const Object = @import("../../ecs/EntityManager.zig").Object;

pub const GpuBuffer = struct {
    pub const deviceAddress = u64;
    allocation: vk.VmaAllocation,
    allocInf: vk.VmaAllocationInfo,
    buffer: vk.VkBuffer,
    gpuAddress: deviceAddress,
    count: u32 = 0,
};

pub const BufferMap = CreateMapArray(GpuBuffer, 100, u32, 100, 0); // 100 Fixed Buffers

pub const BufferManager = struct {
    cpuAlloc: Allocator,
    gpuAlloc: GpuAllocator, //deinit() in ResourceManager

    gpuBuffers: BufferMap = .{},

    pub fn init(cpuAlloc: Allocator, gpuAlloc: GpuAllocator) BufferManager {
        return .{ .cpuAlloc = cpuAlloc, .gpuAlloc = gpuAlloc };
    }

    pub fn deinit(self: *BufferManager) void {
        for (self.gpuBuffers.getElements()) |gpuBuffer| self.destroyGpuBuffer(gpuBuffer);
    }

    pub fn getGpuBuffer(self: *BufferManager, buffId: u8) !GpuBuffer {
        if (self.gpuBuffers.isKeyUsed(buffId) == false) return error.GpuBufferDoesNotExist;
        return self.gpuBuffers.get(buffId);
    }

    pub fn createGpuBuffer(self: *BufferManager, buffId: u8, objects: []Object) !void {
        const bufferSize = objects.len * @sizeOf(Object);

        var buffer = try self.gpuAlloc.allocDefinedBuffer(bufferSize, null, .testBuffer); // CURRENTLY FIXED TEST BUFFER!
        const pMappedData = buffer.allocInf.pMappedData;

        // Check Alignemnt naively (Doesnt catch everything)
        const alignment = @alignOf(Object);
        if (@intFromPtr(pMappedData) % alignment != 0) {
            return error.ImproperAlignment;
        }
        const dataPtr: [*]Object = @ptrCast(@alignCast(pMappedData));
        @memcpy(dataPtr[0..objects.len], objects);

        buffer.count = @intCast(objects.len);
        self.gpuBuffers.set(buffId, buffer);
    }

    pub fn destroyGpuBuffer(self: *const BufferManager, gpuBuffer: GpuBuffer) void {
        self.gpuAlloc.freeGpuBuffer(gpuBuffer.buffer, gpuBuffer.allocation);
    }
};
