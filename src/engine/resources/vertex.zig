const vk = @import("vulkan");

// Vertex structure that matches our shader input layout
pub const Vertex = struct {
    // Describes how vertex data is bound to the pipeline
    pub const binding_description = vk.VertexInputBindingDescription{
        .binding = 0, // Binding point index
        .stride = @sizeOf(Vertex), // Bytes between consecutive vertices
        .input_rate = .vertex, // Move to next data entry for each vertex
    };

    // Describes the format and location of vertex attributes
    pub const attribute_descriptions = [_]vk.VertexInputAttributeDescription{
        .{
            .binding = 0, // Which binding to read from
            .location = 0, // Shader location index
            .format = .r32g32_sfloat, // 2 floats (position)
            .offset = @offsetOf(Vertex, "position"),
        },
        .{
            .binding = 0,
            .location = 1,
            .format = .r32g32b32_sfloat, // 3 floats (color)
            .offset = @offsetOf(Vertex, "color"),
        },
    };

    position: [2]f32, // x, y coordinates
    color: [3]f32, // r, g, b values
};
