const std = @import("std");
const zm = @import("zmath");
const RNGenerator = @import("../core/RNGenerator.zig").RNGenerator;

pub const EntityManager = struct {
    objects: [100]Object,

    pub fn init(rng: *RNGenerator) !EntityManager {
        var objects: [100]Object = undefined;

        for (0..objects.len) |i| {
            const id = rng.intRange(u32, 0, @typeInfo(Object.SDF).@"enum".fields.len - 1);
            std.debug.print("Id {} \n", .{id});

            objects[i] = .{
                .sdfId = @enumFromInt(id),
                .colorR = rng.float(f32),
                .colorG = rng.float(f32),
                .colorB = rng.float(f32),

                .posX = rng.float(f32) * 30 - 15,
                .posY = rng.float(f32) * 30 - 15,
                .posZ = rng.float(f32) * 30 - 15,
                .size = rng.float(f32) + 0.2,
            };
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
    pub const SDF = enum(u32) { sphere, cube, box };

    posX: f32,
    posY: f32,
    posZ: f32,
    size: f32,

    colorR: f32,
    colorG: f32,
    colorB: f32,
    sdfId: SDF,
};
