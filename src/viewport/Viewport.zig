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
};
