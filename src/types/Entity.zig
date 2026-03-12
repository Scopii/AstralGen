pub const Entity = extern struct {
    pub const SDF = enum(u32) { sphere, cube, box };

    posX: f32,
    posY: f32,
    posZ: f32,
    size: f32,

    colorR: f32,
    colorG: f32,
    colorB: f32,
    sdfId: SDF,

    _pad1: u32 = 0,
    _pad2: u32 = 0,
    _pad3: u32 = 0,
    _pad4: u32 = 0,
};
