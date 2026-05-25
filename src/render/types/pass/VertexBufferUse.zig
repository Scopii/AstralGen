const vk = @import("../../../.modules/vk.zig").c;

const BufferEnum = @import("../../../frameBuild/enums.zig").BufferEnum;

pub const VertexBufferUse = struct {
    bufInput: BufferEnum,
    binding: u32,
    stride: u32,
    inputRate: vk.VkVertexInputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,

    pub fn init(bufInput: BufferEnum, binding: u32, stride: u32, inputRate: vk.VkVertexInputRate) VertexBufferUse {
        return .{ .bufInput = bufInput, .binding = binding, .stride = stride, .inputRate = inputRate };
    }
};
