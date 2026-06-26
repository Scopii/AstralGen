const BufPassId = @import("../../../frameBuild/components.zig").BufPassId;
const vk = @import("../../../.modules/vk.zig").c;

pub const IndexBufferUse = struct {
    bufInput: BufPassId,
    indexType: vk.VkIndexType = vk.VK_INDEX_TYPE_UINT32,

    pub fn init(bufInput: BufPassId, indexType: vk.VkIndexType) IndexBufferUse {
        return .{ .bufInput = bufInput, .indexType = indexType };
    }
};
