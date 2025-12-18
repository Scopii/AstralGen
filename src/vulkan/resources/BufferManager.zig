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
        for (self.gpuBuffers.getElements()) |gpuBuffer| self.destroyGpuBuffer(gpuBuffer);
    }

    pub fn getGpuBuffer(self: *BufferManager, buffId: u8) !GpuBuffer {
        if (self.gpuBuffers.isKeyUsed(buffId) == false) return error.GpuBufferDoesNotExist;
        return self.gpuBuffers.get(buffId);
    }

    pub fn createGpuBuffer(self: *BufferManager, buffId: u8, objects: []Object) !void {
        const bufferSize = objects.len * @sizeOf(Object);

        var buffer = try createDefinedBuffer(self.gpuAlloc.handle, self.gpi, bufferSize, null, .testBuffer);
        var allocVmaInf: vk.VmaAllocationInfo = undefined;
        vk.vmaGetAllocationInfo(self.gpuAlloc.handle, buffer.allocation, &allocVmaInf);

        // Check Alignemnt naively (Doesnt catch everything)
        const alignment = @alignOf(Object);
        if (@intFromPtr(allocVmaInf.pMappedData) % alignment != 0) {
            return error.ImproperAlignment;
        }

        const dataPtr: [*]Object = @ptrCast(@alignCast(allocVmaInf.pMappedData));
        @memcpy(dataPtr[0..objects.len], objects);

        buffer.count = @intCast(objects.len);

        self.gpuBuffers.set(buffId, buffer);
    }

    // DOES NOT WORK, WILL CRASH
    // pub fn updateGpuBuffer(self: *const BufferManager, gpuBuffer: GpuBuffer, data: []const u8, offset: vk.VkDeviceSize) !void {
    //     if (offset + data.len > gpuBuffer.size) return error.BufferOverflow;

    //     var allocVmaInf: vk.VmaAllocationInfo = undefined;
    //     vk.vmaGetAllocationInfo(self.gpuAlloc.handle, gpuBuffer.allocation, &allocVmaInf);
    //     const mappedPtr = @as([*]u8, @ptrCast(allocVmaInf.pMappedData));
    //     @memcpy(mappedPtr[offset .. offset + data.len], data);
    // }

    pub fn destroyGpuBuffer(self: *const BufferManager, gpuBuffer: GpuBuffer) void {
        vk.vmaDestroyBuffer(self.gpuAlloc.handle, gpuBuffer.buffer, gpuBuffer.allocation);
    }
};

fn createDefinedBuffer(vma: vk.VmaAllocator, gpi: vk.VkDevice, size: vk.VkDeviceSize, data: ?[]const u8, bufferType: enum { storage, uniform, testBuffer }) !GpuBuffer {
    const bufferUsage: u32 = switch (bufferType) {
        .storage, .testBuffer => vk.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT | vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        .uniform => vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT,
    };
    const memUsage: u32 = switch (bufferType) {
        .storage => vk.VMA_MEMORY_USAGE_GPU_ONLY,
        .uniform, .testBuffer => vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
    };
    const memFlags: u32 = switch (bufferType) {
        .uniform,
        => vk.VMA_ALLOCATION_CREATE_MAPPED_BIT,
        .testBuffer => vk.VMA_ALLOCATION_CREATE_MAPPED_BIT | vk.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
        .storage => 0, // Storage buffers should not be mapped
    };
    return createBuffer(vma, gpi, size, data, bufferUsage, memUsage, memFlags);
}

fn createBuffer(vma: vk.VmaAllocator, gpi: vk.VkDevice, size: vk.VkDeviceSize, data: ?[]const u8, bufferUsage: vk.VkBufferUsageFlags, memUsage: vk.VmaMemoryUsage, memFlags: vk.VmaAllocationCreateFlags) !GpuBuffer {
    const bufferInf = vk.VkBufferCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = bufferUsage,
        .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
    };
    var buffer: vk.VkBuffer = undefined;
    var allocation: vk.VmaAllocation = undefined;
    var allocVmaInf: vk.VmaAllocationInfo = undefined;
    const allocInf = vk.VmaAllocationCreateInfo{ .usage = memUsage, .flags = memFlags };
    try check(vk.vmaCreateBuffer(vma, &bufferInf, &allocInf, &buffer, &allocation, &allocVmaInf), "Failed to create buffer reference buffer");

    const addressInf = vk.VkBufferDeviceAddressInfo{ .sType = vk.VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO, .buffer = buffer };
    const deviceAddress = vk.vkGetBufferDeviceAddress(gpi, &addressInf);

    // Initialize with data if provided
    if (data) |initData| {
        const mappedPtr = @as([*]u8, @ptrCast(allocVmaInf.pMappedData));
        @memcpy(mappedPtr[0..initData.len], initData);
    }

    return GpuBuffer{
        .buffer = buffer,
        .allocation = allocation,
        .gpuAddress = deviceAddress,
        .size = size,
    };
}
