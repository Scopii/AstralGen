const std = @import("std");
const RNGenerator = @import("../core/RNGenerator.zig").RNGenerator;

const objCount = 3;

pub const EntityManager = struct {
    objects: [objCount]Object,

    pub fn init(rng: *RNGenerator) !EntityManager {
        var objects: [objCount]Object = undefined;

        for (0..objects.len) |i| {
            const id = rng.intRange(u32, 0, @typeInfo(Object.SDF).@"enum".fields.len - 1);

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
        }
        std.debug.print("Created {} Objects\n", .{objects.len});
        return .{ .objects = objects };
    }

    pub fn deinit(_: *EntityManager) void {}

    pub fn getObjects(self: *EntityManager) []Object {
        return &self.objects;
    }
};

pub const Object = extern struct {
    pub const SDF = enum(u32) { sphere, cube, box };

    posX: f32,
    posY: f32,
    posZ: f32,
    size: f32,

    colorR: f32,
    colorG: f32,
    colorB: f32,
    sdfId: SDF,

    _pad1: u32 = 0,
    _pad2: u32 = 0,
    _pad3: u32 = 0,
    _pad4: u32 = 0,
};
