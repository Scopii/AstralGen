const std = @import("std");
const vk = @import("../../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const Context = @import("../Context.zig").Context;
const DescriptorManager = @import("DescriptorManager.zig").DescriptorManager;
const ResourceState = @import("../RenderGraph.zig").ResourceState;
const GpuAllocator = @import("GpuAllocator.zig").GpuAllocator;
const rc = @import("../../configs/renderConfig.zig");
const ve = @import("../Helpers.zig");
const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;

pub const PushConstants = extern struct {
    runTime: f32 = 0,
    deltaTime: f32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    resourceSlots: [14]ResourceSlot = undefined, // 7 is 64
};

pub const ResourceSlot = extern struct { index: u32 = 0, count: u32 = 0 };

pub const ResourceInf = struct {
    id: u32,
    memUse: ve.MemUsage,
    inf: union(enum) { imgInf: ImgInf, bufInf: BufInf },

    pub const ImgInf = struct { extent: vk.VkExtent3D, format: c_uint = rc.RENDER_IMG_FORMAT, imgType: ve.ImgType };
    pub const BufInf = struct { dataSize: u64 = 0, length: u32, bufType: ve.BufferType };

    pub fn Buffer(id: u32, memUsage: ve.MemUsage, bufType: ve.BufferType, length: u32, comptime T: type) ResourceInf {
        return ResourceInf{ .id = id, .memUse = memUsage, .inf = .{ .bufInf = .{
            .bufType = bufType,
            .length = length,
            .dataSize = @sizeOf(T),
        } } };
    }

    pub fn Image(id: u32, memUsage: ve.MemUsage, imgType: ve.ImgType, width: u32, height: u32, depth: u32, format: c_int) ResourceInf {
        return ResourceInf{ .id = id, .memUse = memUsage, .inf = .{ .imgInf = .{
            .imgType = imgType,
            .extent = .{
                .width = width,
                .height = height,
                .depth = depth,
            },
            .format = format,
        } } };
    }
};

pub const Resource = struct {
    resourceType: ResourceUnion,
    bindlessIndex: u32,
    state: ResourceState = .{},

    pub const ResourceUnion = union(enum) {
        gpuBuf: GpuBuffer,
        gpuImg: GpuImage,
    };
    pub const GpuImage = struct {
        imgInf: ResourceInf.ImgInf,
        allocation: vk.VmaAllocation,
        img: vk.VkImage,
        view: vk.VkImageView,
    };
    pub const GpuBuffer = struct {
        allocation: vk.VmaAllocation,
        allocInf: vk.VmaAllocationInfo,
        buffer: vk.VkBuffer,
        gpuAddress: u64,
        count: u32 = 0,
    };

    pub fn getResourceSlot(self: *Resource) ResourceSlot {
        var resSlot = ResourceSlot{};

        switch (self.resourceType) {
            .gpuBuf => |gpuBuf| {
                resSlot.index = self.bindlessIndex;
                resSlot.count = gpuBuf.count;
            },
            .gpuImg => |_| {
                resSlot.index = self.bindlessIndex;
                resSlot.count = 1;
            },
        }
        return resSlot;
    }
};
