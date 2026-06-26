const vk = @import("../../../.modules/vk.zig").c;

pub const IndexBufferSlot = struct {
    bufInput: []const u8,
    indexType: vk.VkIndexType = vk.VK_INDEX_TYPE_UINT32,

    pub fn init(bufInput: []const u8, indexType: vk.VkIndexType) IndexBufferSlot {
        return .{ .bufInput = bufInput, .indexType = indexType };
    }
};
