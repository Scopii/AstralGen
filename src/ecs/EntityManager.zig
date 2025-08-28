const std = @import("std");
const zm = @import("zmath");
const RNGenerator = @import("../core/RNGenerator.zig").RNGenerator;

pub const EntityManager = struct {
    objects: [100]Object,

    pub fn init(rng: *RNGenerator) !EntityManager {
        var objects: [100]Object = undefined;

        for (0..objects.len) |i| {
            const posX = rng.float(f32) * 100;
            const posY = rng.float(f32) * 100;
            const posZ = rng.float(f32) * 100;
            objects[i] = .{ .posAndSize = zm.f32x4(posX - 50, posY - 50, posZ - 50, 0.5) };
            std.debug.print("Assigned Object Array Index {}\n", .{i});
        }
        return .{ .objects = objects };
    }

    pub fn deinit(_: *EntityManager) void {}

    pub fn getObjects(self: *EntityManager) []Object {
        return &self.objects;
    }
};

pub const Object = struct {
    //sdfId: enum(u32) { sphere, cube, triangle },
    //boundingSize: f32 = 1,
    posAndSize: zm.Vec = zm.f32x4(0, 0, 0, 0.5),
};
