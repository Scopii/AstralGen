const RNGenerator = @import("../core/RNGenerator.zig").RNGenerator;
const LinkedMap = @import("../structures/LinkedMap.zig").LinkedMap;
const Entity = @import("../entity/Entity.zig").Entity;
const std = @import("std");

const objCount = 30;

pub const EntityState = struct {
    entitys: LinkedMap(Entity, objCount, u32, objCount, 0) = .{},
};
