const zm = @import("zmath");
const BufId = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufId;

pub const Transform = struct {
    pos: zm.Vec = zm.f32x4(0, 0, -5, 0),
    up: zm.Vec = zm.f32x4(0, 1, 0, 0),
    pitch: f32 = 0.0,
    yaw: f32 = 0.0,
    scale: zm.Vec = zm.f32x4(1, 1, 1, 0),
    isDirty: bool = true,
};

pub const CameraComp = struct {
    fov: f32 = 100.0,
    aspectRatio: f32 = 16.0 / 9.0,
    near: f32 = 0.1,
    far: f32 = 1000.0,
    bufId: BufId, 
};

pub const RenderableComp = struct {
    pub const SDF = enum(u32) { sphere, cube, box };
    sdfId: SDF,
    colorR: f32,
    colorG: f32,
    colorB: f32,
    size: f32,
};