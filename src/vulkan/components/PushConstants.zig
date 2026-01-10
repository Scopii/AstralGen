
pub const PushConstants = extern struct {
    runTime: f32 = 0,
    deltaTime: f32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    resourceSlots: [14]ResourceSlot = undefined, 
};

pub const ResourceSlot = extern struct { index: u32 = 0, count: u32 = 0 };
