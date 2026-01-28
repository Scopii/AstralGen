
pub const ReadbackData = extern struct {
    runtime: f32,
    deltaTime: f32,
    width: u32,
    height: u32,
};

pub const IndirectData = extern struct {
    x: u32,
    y: u32,
    z: u32,
};

pub const SpecData = extern struct {
    threadX: u32, 
    threadY: u32, 
    threadZ: u32, 
};