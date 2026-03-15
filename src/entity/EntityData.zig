const LinkedMap = @import("../.structures/LinkedMap.zig").LinkedMap;
const Entity = @import("../entity/Entity.zig").Entity;
const rc = @import("../.configs/renderConfig.zig");

pub const EntityData = struct {
    entitys: LinkedMap(Entity, rc.ENTITY_COUNT, u32, rc.ENTITY_COUNT, 0) = .{},
};
