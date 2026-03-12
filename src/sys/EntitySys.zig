const RNGenerator = @import("../core/RNGenerator.zig").RNGenerator;
const std = @import("std");

const EntityState = @import("../state/EntityState.zig").EntityState;
const EntityId = @import("../ids/entityId.zig").EntityId;
const Entity = @import("../types/Entity.zig").Entity;

const objCount = 30;

pub const EntitySys = struct {
    pub fn init(entityState: *EntityState, rng: *RNGenerator) !void {
        for (0..objCount) |i| {
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

            entityState.entitys.upsert(@intCast(i), entity);
        }
        std.debug.print("Created {} Objects\n", .{entityState.entitys.getLength()});
    }

    pub fn deinit(_: *EntityState) void {}

    pub fn addEntity(entityState: *EntityState, entityId: EntityId, entity: Entity) !void {
        entityState.entitys.upsert(entityId.val, entity);
    }

    pub fn getObjects(entityState: *EntityState) []Entity {
        return entityState.entitys.getItems();
    }
};
