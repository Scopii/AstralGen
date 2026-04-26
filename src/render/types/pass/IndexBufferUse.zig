const BufferMeta = @import("../res/BufferMeta.zig").BufferMeta;
const vk = @import("../../../.modules/vk.zig").c;

pub const IndexBufferUse = struct {
    bufId: BufferMeta.BufId,
    indexType: vk.VkIndexType = vk.VK_INDEX_TYPE_UINT32,

    pub fn init(bufId: BufferMeta.BufId, indexType: vk.VkIndexType) IndexBufferUse {
        return .{ .bufId = bufId, .indexType = indexType };
    }
};
