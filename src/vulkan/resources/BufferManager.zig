const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const vkFn = @import("../../modules/vk.zig");
const Allocator = std.mem.Allocator;
const Context = @import("../Context.zig").Context;
const VkAllocator = @import("../vma.zig").VkAllocator;
const check = @import("../error.zig").check;
const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;
const Object = @import("../../ecs/EntityManager.zig").Object;

pub const GpuBuffer = struct {
    pub const deviceAddress = u64;
    allocation: vk.VmaAllocation,
    buffer: vk.VkBuffer,
    gpuAddress: deviceAddress,
    size: vk.VkDeviceSize,
    count: u32 = 0,
};

pub const BufferMap = CreateMapArray(GpuBuffer, 100, u32, 100, 0); // 100 Fixed Buffers

pub const BufferManager = struct {
    cpuAlloc: Allocator,
    gpuAlloc: VkAllocator,
    gpi: vk.VkDevice,
    gpu: vk.VkPhysicalDevice,

    gpuBuffers: BufferMap = .{},

    pub fn init(cpuAlloc: Allocator, gpuAlloc: VkAllocator, gpi: vk.VkDevice, gpu: vk.VkPhysicalDevice) BufferManager {
        return .{ .cpuAlloc = cpuAlloc, .gpuAlloc = gpuAlloc, .gpi = gpi, .gpu = gpu };
    }

    pub fn deinit(self: *BufferManager) void {
        for (self.gpuBuffers.getElements()) |gpuBuffer| self.destroyGpuImageDirect(gpuBuffer);
    }
};
