const EntityData = @import("../entity/EntityData.zig").EntityData;
const EntityQueue = @import("../entity/EntityQueue.zig").EntityQueue;
const RNGenerator = @import("../core/RNGenerator.zig").RNGenerator;
const Entity = @import("../entity/Entity.zig").Entity;
const std = @import("std");

pub const EntityId = packed struct { val: u32 };

pub const EntitySys = struct {
    pub fn update(entityData: *EntityData, entityQueue: *EntityQueue, rng: *RNGenerator) void {
        for (entityQueue.get()) |entityEvent| {
            switch (entityEvent) {
                .addEntity => |inf| addEntity(entityData, inf.entityId, inf.entity),
                .addRandomEntity => |id| addRandomEntity(entityData, id, rng),
                .removeEntity => |id| removeEntity(entityData, id),
            }
        }
        entityQueue.clear();
    }

    fn addEntity(entityData: *EntityData, entityId: EntityId, entity: Entity) void {
        entityData.entitys.upsert(entityId.val, entity);
    }

    fn addRandomEntity(entityData: *EntityData, entityId: EntityId, rng: *RNGenerator) void {
        const id = rng.intRangeFixed(u32, 0, @typeInfo(Entity.SDF).@"enum".fields.len - 1);

        const entity = Entity{
            .sdfId = @enumFromInt(id),
            .colorR = rng.floatFixed(f32),
            .colorG = rng.floatFixed(f32),
            .colorB = rng.floatFixed(f32),

            .posX = rng.floatFixed(f32) * 30 - 15,
            .posY = rng.floatFixed(f32) * 30 - 15,
            .posZ = rng.floatFixed(f32) * 30 - 15,
            .size = rng.floatFixed(f32) + 0.2,
        };

        entityData.entitys.upsert(entityId.val, entity);
        std.debug.print("Created Entity (ID {}) (Entity Count {}) \n", .{ entityId.val, entityData.entitys.getLength() });
    }

    pub fn getEntitys(entityData: *EntityData) []Entity {
        return entityData.entitys.getItems();
    }

    fn removeEntity(entityData: *EntityData, entityId: EntityId) void {
        entityData.entitys.remove(entityId.val);
    }
};
