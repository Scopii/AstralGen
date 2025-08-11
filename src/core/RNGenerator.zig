pub const std = @import("std");

pub const RNGenerator = struct {
    prng: type,
    random: std.rand.Random,

    pub fn init(comptime PrngType: type, seed: u64) RNGenerator {
        const prng = PrngType.init(seed);
        const zigRandInterface = std.rand.Random.init(&prng);

        return .{
            .prng = prng,
            .random = zigRandInterface,
        };
    }

    // integer of the specified type.
    pub fn int(self: *RNGenerator, comptime T: type) T {
        return self.random.int(T);
    }

    // integer within the given range (inclusive).
    pub fn intRange(self: *RNGenerator, comptime T: type, min: T, max: T) T {
        return self.random.intRange(T, min, max);
    }

    // float of the specified type (0.0 <= x < 1.0).
    pub fn float(self: *RNGenerator, comptime T: type) T {
        return self.random.float(T);
    }

    // boolean (true or false).
    pub fn boolean(self: *RNGenerator) bool {
        return self.random.boolean();
    }

    // element from a slice.
    pub fn choice(self: *RNGenerator, comptime T: type, items: []const T) T {
        return self.random.choice(items);
    }

    // fills a slice with random bytes
    pub fn bytes(self: *RNGenerator, buf: []u8) void {
        self.random.bytes(buf);
    }
};
