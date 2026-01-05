const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const Context = @import("../Context.zig").Context;
const DescriptorManager = @import("DescriptorManager.zig").DescriptorManager;
const ResourceSlot = @import("Resource.zig").ResourceSlot;
const ResourceState = @import("../RenderGraph.zig").ResourceState;
const GpuAllocator = @import("GpuAllocator.zig").GpuAllocator;
const rc = @import("../../configs/renderConfig.zig");
const ve = @import("../Helpers.zig");
const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;


pub const Buffer = struct {
    buffer: vk.VkBuffer,
    allocation: vk.VmaAllocation,
    allocInf: vk.VmaAllocationInfo,
    gpuAddress: u64,
    count: u32 = 0,
    bindlessIndex: u32,
    state: ResourceState = .{},

    pub fn getResourceSlot(self: *Buffer) ResourceSlot {
        return ResourceSlot{ .index = self.bindlessIndex, .count = self.count };
    }
};
