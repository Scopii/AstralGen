const BufferMeta = @import("../res/BufferMeta.zig").BufferMeta;
const vk = @import("../../../.modules/vk.zig").c;
const BufId = BufferMeta.BufId;

pub const VertexBufferUse = struct {
    bufId: BufferMeta.BufId,
    binding: u32,
    stride: u32,
    inputRate: vk.VkVertexInputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,

    pub fn init(bufId: BufferMeta.BufId, binding: u32, stride: u32, inputRate: vk.VkVertexInputRate) VertexBufferUse {
        return .{ .bufId = bufId, .binding = binding, .stride = stride, .inputRate = inputRate };
    }
};
