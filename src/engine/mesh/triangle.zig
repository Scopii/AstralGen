const Vertex = @import("../resources/vertex.zig").Vertex;

// Triangle vertex data (in normalized device coordinates: -1 to 1)
pub const triangle_vertices = [_]Vertex{
    .{ .position = .{ 0.0, -0.5 }, .color = .{ 1.0, 0.0, 0.0 } }, // Top vertex (red)
    .{ .position = .{ 0.5, 0.5 }, .color = .{ 0.0, 1.0, 0.0 } }, // Bottom right (green)
    .{ .position = .{ -0.5, 0.5 }, .color = .{ 0.0, 0.0, 1.0 } }, // Bottom left (blue)
};
