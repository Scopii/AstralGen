const BufId = @import("../../../.configs/idConfig.zig").BufId;
const rc = @import("../../../.configs/renderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const vhE = @import("../../help/Enums.zig");
const std = @import("std");

pub const BufferState = struct {
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
};

pub const BufInf = struct {
    id: BufId,
    mem: vhE.MemUsage,
    elementSize: u32,
    len: u32,
    typ: vhE.BufferType,
    update: vhE.UpdateType,
    resize: vhE.ResizeType = .Block,

    pub fn create(bufInf: BufInf) BufInf {
        return bufInf;
    }
};

pub const BufDesc = struct {
    share: enum { persistent, transient },
    mem: vhE.MemUsage,
    elementSize: u32,
    len: u32,
    typ: vhE.BufferType,
    update: vhE.UpdateType,
    resize: vhE.ResizeType = .Block,

    pub fn guessMemoryCost(self: *const BufDesc) u64 {
        const rawMemory = @as(u64, self.elementSize) * @as(u64, self.len);

        return switch (self.update) {
            .Rarely => rawMemory,
            .Often, .PerFrame => if (self.share == .transient and rc.FRAME_GRAPH_TRANSIENTS_PER_FRAME_IN_FLIGHT) rawMemory * rc.MAX_IN_FLIGHT else rawMemory,

            // .Rarely, .Often, .PerFrame => rawMemory,
        };
    }
};

pub const SimpleBuffer = struct {
    descIndex: ?u31 = null,
    handle: vk.VkBuffer,
    allocation: vk.VmaAllocation,
    gpuAddress: u64,
    size: vk.VkDeviceSize,
    mappedPtr: ?*anyopaque,
};

pub const Buffer = struct {
    typ: vhE.BufferType,
    update: vhE.UpdateType,
    resize: vhE.ResizeType,
    mem: vhE.MemUsage,
    elementSize: u32,

    descIndex: ?u31 = null,
    handle: vk.VkBuffer,
    allocation: vk.VmaAllocation,
    gpuAddress: u64,
    size: vk.VkDeviceSize,
    mappedPtr: ?*anyopaque,
};
