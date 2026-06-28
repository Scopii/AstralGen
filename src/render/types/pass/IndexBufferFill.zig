const vk = @import("../../../.modules/vk.zig").c;

const BufId = @import("../res/BufferMeta.zig").BufferMeta.BufId;

pub const IndexBufferFill = struct {
    bufId: BufId,
    indexType: vk.VkIndexType = vk.VK_INDEX_TYPE_UINT32,

    pub fn init(bufId: BufId, indexType: vk.VkIndexType) IndexBufferFill {
        return .{ .bufId = bufId, .indexType = indexType };
    }
};
