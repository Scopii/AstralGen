const TexId = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexId;
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

    passSlice: []const PassEnum,
    blitPass: PassEnum,

    pub fn calcViewWidth(self: *const Viewport, swapchainWidth: u32) u32 {
        return @intFromFloat(@as(f32, @floatFromInt(swapchainWidth)) * self.areaWidth);
    }

    pub fn calcViewHeight(self: *const Viewport, swapchainHeight: u32) u32 {
        return @intFromFloat(@as(f32, @floatFromInt(swapchainHeight)) * self.areaHeight);
    }

    pub fn calcViewX(self: *const Viewport, swapchainWidth: u32) i32 {
        return @intFromFloat(@as(f32, @floatFromInt(swapchainWidth)) * self.areaX);
    }

    pub fn calcViewY(self: *const Viewport, swapchainHeight: u32) i32 {
        return @intFromFloat(@as(f32, @floatFromInt(swapchainHeight)) * self.areaY);
    }
};
