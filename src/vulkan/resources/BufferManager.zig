const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const GpuAllocator = @import("GpuAllocator.zig").GpuAllocator;
const Object = @import("../../ecs/EntityManager.zig").Object;
const renderCon = @import("../../configs/renderConfig.zig");
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
    pub const BufferMap = CreateMapArray(GpuBuffer, renderCon.GPU_BUF_COUNT, u32, renderCon.GPU_BUF_COUNT, 0);

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

    pub fn createGpuBuffer(self: *BufferManager, comptime gpuBufConfigs: renderCon.GpuBufferInfo) !void {
        const buffer = try self.gpuAlloc.allocDefinedBuffer(gpuBufConfigs);
        self.gpuBuffers.set(gpuBufConfigs.descBinding.buffId, buffer);
    }

    pub fn updateGpuBuffer(self: *BufferManager, comptime gpuBufConfig: renderCon.GpuBufferInfo, data: []const gpuBufConfig.dataType) !void {
        const buffId = gpuBufConfig.descBinding.buffId;
        var buffer = try self.getGpuBuffer(buffId);
        const pMappedData = buffer.allocInf.pMappedData;
        // Check Alignemnt naively (Doesnt catch everything)
        const alignment = @alignOf(gpuBufConfig.dataType);
        if (@intFromPtr(pMappedData) % alignment != 0) {
            return error.ImproperAlignment;
        }
        const dataPtr: [*]gpuBufConfig.dataType = @ptrCast(@alignCast(pMappedData));
        @memcpy(dataPtr[0..data.len], data);

        buffer.count = @intCast(data.len);
        self.gpuBuffers.set(buffId, buffer);
    }

    pub fn destroyGpuBuffer(self: *const BufferManager, gpuBuffer: GpuBuffer) void {
        self.gpuAlloc.freeGpuBuffer(gpuBuffer.buffer, gpuBuffer.allocation);
    }
};
