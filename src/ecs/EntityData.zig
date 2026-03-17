const LinkedMap = @import("../.structures/LinkedMap.zig").LinkedMap;
const RNGenerator = @import("../core/RNGenerator.zig").RNGenerator;
const rc = @import("../.configs/renderConfig.zig");
const comp = @import("Components.zig");
const zm = @import("zmath");

pub const EntityId = packed struct { val: u32 };

pub const EntityData = struct {
    nextEntityId: u32 = 1,

    transforms: LinkedMap(comp.Transform, rc.ENTITY_MAX, u32, rc.ENTITY_MAX, 0) = .{},
    cameras: LinkedMap(comp.CameraComp, rc.ENTITY_MAX, u32, rc.ENTITY_MAX, 0) = .{},
    renderables: LinkedMap(comp.RenderableComp, rc.ENTITY_MAX, u32, rc.ENTITY_MAX, 0) = .{},

    pub fn creatEntityId(self: *EntityData) EntityId {
        const id = self.nextEntityId;
        self.nextEntityId += 1;
        return .{ .val = id };
    }

    pub fn createRandomRenderEntity(self: *EntityData, rng: *RNGenerator) EntityId {
        const entityId = self.creatEntityId();

        self.transforms.upsert(entityId.val, .{
            .pos = zm.f32x4(
                rng.floatFixed(f32) * 30 - 15,
                rng.floatFixed(f32) * 30 - 15,
                rng.floatFixed(f32) * 30 - 15,
                0,
            ),
            .scale = zm.f32x4(
                rng.floatFixed(f32) + 0.2,
                rng.floatFixed(f32) + 0.2,
                rng.floatFixed(f32) + 0.2,
                0,
            ),
        });

        self.renderables.upsert(entityId.val, .{
            .sdfId = @enumFromInt(rng.intRangeFixed(u32, 0, 2)),
            .colorR = rng.floatFixed(f32),
            .colorG = rng.floatFixed(f32),
            .colorB = rng.floatFixed(f32),
            .size = rng.floatFixed(f32) + 0.2,
        });

        return entityId;
    }

    pub fn createCameraEntity(self: *EntityData, transform: comp.Transform, camera: comp.CameraComp) EntityId {
        const entityId = self.creatEntityId();
        self.transforms.upsert(entityId.val, transform);
        self.cameras.upsert(entityId.val, camera);
        return entityId;
    }

    pub fn destroyEntity(self: *EntityData, id: EntityId) void { // Maybe check is handled?
        if (self.transforms.isKeyUsed(id.val)) self.transforms.remove(id.val);
        if (self.cameras.isKeyUsed(id.val)) self.cameras.remove(id.val);
        if (self.renderables.isKeyUsed(id.val)) self.renderables.remove(id.val);
    }
};
