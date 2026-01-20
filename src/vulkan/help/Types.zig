
pub const ReadbackData = struct {
    runtime: f32,
    deltaTime: f32,
    width: u32,
    height: u32,
};

pub const IndirectData = struct {
    x: u32,
    y: u32,
    z: u32,
    count: u32,
};
