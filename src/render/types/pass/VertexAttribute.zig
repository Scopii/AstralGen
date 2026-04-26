const vk = @import("../../../.modules/vk.zig").c;

pub const VertexAttribute = struct {
    location: u32,
    binding: u32, // which VertexBufferUse this reads from
    format: vk.VkFormat,
    offset: u32,

    pub fn init(location: u32, binding: u32, format: vk.VkFormat, offset: u32) VertexAttribute {
        return .{ .location = location, .binding = binding, .format = format, .offset = offset };
    }
};
