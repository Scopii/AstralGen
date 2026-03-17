pub const EngineData = struct {
    time: @import("time/TimeData.zig").TimeData = .{},
    input: @import("input/InputData.zig").InputData = .{},
    entityData: @import("ecs/EntityData.zig").EntityData = .{},
    shader: @import("shader/ShaderData.zig").ShaderData = .{},
    window: @import("window/WindowData.zig").WindowData = .{},
};
