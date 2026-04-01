const ViewportId = @import("ViewportSys.zig").ViewportId;
const EntityId = @import("../ecs/EntityData.zig").EntityId;
const TexId = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexId;
const Pass = @import("../render/types/base/Pass.zig").Pass;

pub const Viewport = struct {
    sourceTexId: TexId,
    areaX: f32 = 0.0,
    areaY: f32 = 0.0,
    areaWidth: f32 = 1.0,
    areaHeight: f32 = 1.0,
    cameraEntity: ?EntityId,

    pub fn calcViewArea(self: *const Viewport, swapchainWidth: u32, swapchainHeight: u32) struct { width: u32, height: u32 } {
        return .{
            .width = @intFromFloat(@as(f32, @floatFromInt(swapchainWidth)) * self.areaWidth),
            .height = @intFromFloat(@as(f32, @floatFromInt(swapchainHeight)) * self.areaHeight),
        };
    }

    pub fn calcViewOffset(self: *const Viewport, swapchainWidth: u32, swapchainHeight: u32) struct { x: i32, y: i32 } {
        return .{
            .x = @intFromFloat(@as(f32, @floatFromInt(swapchainWidth)) * self.areaX),
            .y = @intFromFloat(@as(f32, @floatFromInt(swapchainHeight)) * self.areaY),
        };
    }
};
