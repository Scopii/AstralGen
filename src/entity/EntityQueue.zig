const FixedList = @import("../.structures/FixedList.zig").FixedList;
const std = @import("std");
const EntityId = @import("EntitySys.zig").EntityId;
const Entity = @import("Entity.zig").Entity;

pub const EntityQueue = struct {
    entityEvents: FixedList(EntityEvent, 127) = .{},

    pub fn append(self: *EntityQueue, entityEvent: EntityEvent) void {
        self.entityEvents.append(entityEvent) catch |err| std.debug.print("InputQueue.appendEvent failed: {}\n", .{err});
    }

    pub fn get(self: *EntityQueue) []const EntityEvent {
        return self.entityEvents.constSlice();
    }

    pub fn clear(self: *EntityQueue) void {
        self.entityEvents.clear();
    }
};

pub const EntityEvent = union(enum) {
    addEntity: struct { entityId: EntityId, entity: Entity },
    addRandomEntity: EntityId,
    removeEntity: EntityId,
};
