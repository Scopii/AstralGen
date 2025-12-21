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
};
