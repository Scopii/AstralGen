const vk = @import("../../../.modules/vk.zig").c;

pub const VertexBufferSlot = struct {
    bufInput: []const u8,
    binding: u32,
    stride: u32,
    inputRate: vk.VkVertexInputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,

    pub fn init(bufInput: []const u8, binding: u32, stride: u32, inputRate: vk.VkVertexInputRate) VertexBufferSlot {
        return .{ .bufInput = bufInput, .binding = binding, .stride = stride, .inputRate = inputRate };
    }
};
