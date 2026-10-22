const BufPassId = @import("../../../.configs/idConfig.zig").BufPassId;
const BufId = @import("../../../.configs/idConfig.zig").BufId;
const vk = @import("../../../.modules/vk.zig").c;

pub const IndexBufferUse = struct {
    bufId: BufId,
    indexType: vk.VkIndexType = vk.VK_INDEX_TYPE_UINT32,
};

pub const IndexBufferFill = struct {
    bufPassId: BufPassId,
    indexType: vk.VkIndexType = vk.VK_INDEX_TYPE_UINT32,
};

pub const IndexBufferSlot = struct {
    bufInput: []const u8,
    indexType: vk.VkIndexType = vk.VK_INDEX_TYPE_UINT32,

    pub fn init(bufInput: []const u8, indexType: vk.VkIndexType) IndexBufferSlot {
        return .{ .bufInput = bufInput, .indexType = indexType };
    }
};
