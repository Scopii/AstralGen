const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const GpuAllocator = @import("GpuAllocator.zig").GpuAllocator;
const Object = @import("../../ecs/EntityManager.zig").Object;
const rc = @import("../../configs/renderConfig.zig");
const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;

pub const GpuBuffer = struct {
    pub const deviceAddress = u64;
    allocation: vk.VmaAllocation,
    allocInf: vk.VmaAllocationInfo,
    buffer: vk.VkBuffer,
    gpuAddress: deviceAddress,
    count: u32 = 0,
};

pub const BufferManager = struct {
    pub const BufferMap = CreateMapArray(GpuBuffer, rc.GPU_BUF_MAX, u32, rc.GPU_BUF_MAX, 0);

    cpuAlloc: Allocator,
    gpuAlloc: GpuAllocator, //deinit() in ResourceManager

    gpuBuffers: BufferMap = .{},

    pub fn init(cpuAlloc: Allocator, gpuAlloc: GpuAllocator) BufferManager {
        return .{ .cpuAlloc = cpuAlloc, .gpuAlloc = gpuAlloc };
    }

    pub fn deinit(self: *BufferManager) void {
        for (self.gpuBuffers.getElements()) |gpuBuffer| self.destroyGpuBuffer(gpuBuffer);
    }

    pub fn getGpuBuffer(self: *BufferManager, buffId: u32) !GpuBuffer {
        if (self.gpuBuffers.isKeyUsed(buffId) == false) return error.GpuBufferDoesNotExist;
        return self.gpuBuffers.get(buffId);
    }

    pub fn createGpuBuffer(self: *BufferManager, bindingInf: rc.ResourceSchema.BufferResource) !void {
        const buffer = try self.gpuAlloc.allocDefinedBuffer(bindingInf);
        self.gpuBuffers.set(bindingInf.binding, buffer);
    }

    pub fn updateGpuBuffer(self: *BufferManager, bindingInf: rc.ResourceSchema.BufferResource, data: anytype) !void {
        const T = std.meta.Child(@TypeOf(data));
        if (@sizeOf(T) != bindingInf.elementSize) {
            std.debug.print("Error: Size mismatch! Config expects {} bytes, Data is {} bytes\n", .{ bindingInf.elementSize, @sizeOf(T) });
            return error.TypeMismatch;
        }
        const buffId = bindingInf.binding;
        var buffer = try self.getGpuBuffer(buffId);
        const pMappedData = buffer.allocInf.pMappedData;
        // Simple alignment check
        const alignment = @alignOf(T);
        if (@intFromPtr(pMappedData) % alignment != 0) {
            return error.ImproperAlignment;
        }
        // Copy
        const dataPtr: [*]T = @ptrCast(@alignCast(pMappedData));
        @memcpy(dataPtr[0..data.len], data);
        // Update
        buffer.count = @intCast(data.len);
        self.gpuBuffers.set(buffId, buffer);
    }

    pub fn destroyGpuBuffer(self: *const BufferManager, gpuBuffer: GpuBuffer) void {
        self.gpuAlloc.freeGpuBuffer(gpuBuffer.buffer, gpuBuffer.allocation);
    }
};
