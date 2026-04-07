const TexId = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexId;
const PassStruct = @import("../frameBuild/FrameBuildSys.zig").PassStruct;
const PassEnum = @import("../frameBuild/FrameBuildSys.zig").PassEnum;
const EntityId = @import("../ecs/EntityData.zig").EntityId;

pub const Viewport = struct {
    name: []const u8,
    sourceTexId: TexId,
    areaX: f32 = 0.0,
    areaY: f32 = 0.0,
    areaWidth: f32 = 1.0,
    areaHeight: f32 = 1.0,
    cameraEntity: ?EntityId,

    passMask: PassStruct = .{},
    blitPass: PassEnum,

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
