pub const EngineData = struct {
    ui: @import("ui/UiData.zig").UiData = .{},
    time: @import("time/TimeData.zig").TimeData = .{},
    input: @import("input/InputData.zig").InputData = .{},
    entityData: @import("ecs/EntityData.zig").EntityData = .{},
    shader: @import("shader/ShaderData.zig").ShaderData = .{},
    window: @import("window/WindowData.zig").WindowData = .{},
    viewport: @import("viewport/ViewportData.zig").ViewportData = .{},
    frameBuild: @import("frameBuild/FrameBuildData.zig").FrameBuildData = .{},
};
