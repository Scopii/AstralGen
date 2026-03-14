const RNGenerator = @import("../core/RNGenerator.zig").RNGenerator;
const LinkedMap = @import("../.structures/LinkedMap.zig").LinkedMap;
const Entity = @import("../entity/Entity.zig").Entity;
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");


pub const EntityData = struct {
    entitys: LinkedMap(Entity, rc.ENTITY_COUNT, u32, rc.ENTITY_COUNT, 0) = .{},
};
