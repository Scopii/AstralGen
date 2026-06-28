const BufId = @import("../../../.configs/idConfig.zig").BufId;
const vk = @import("../../../.modules/vk.zig").c;

pub const VertexBufferFill = struct {
    bufId: BufId,
    binding: u32,
    stride: u32,
    inputRate: vk.VkVertexInputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,

    pub fn init(bufId: BufId, binding: u32, stride: u32, inputRate: vk.VkVertexInputRate) VertexBufferFill {
        return .{ .bufId = bufId, .binding = binding, .stride = stride, .inputRate = inputRate };
    }
};
