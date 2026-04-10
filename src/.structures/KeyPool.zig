const std = @import("std");
const FixedList = @import("FixedList.zig").FixedList;

fn FindSmallestIntType(number: usize) type {
    return std.math.IntFittingRange(0, number);
}

pub fn KeyPool(comptime capacity: u32, comptime keyType: type) type {
    const smallKeyType = FindSmallestIntType(capacity);
    const indexType = FindSmallestIntType(capacity + 1);

    return struct {
        const Self = @This();
        len: indexType = 0,
        freeList: FixedList(smallKeyType, capacity) = .{},

        pub fn reserveKey(self: *Self) keyType {
            std.debug.assert(self.len < capacity);
            if (self.freeList.pop()) |key| {
                self.len += 1;
                return @intCast(key);
            } else {
                const key = self.len;
                self.len += 1;
                return @intCast(key);
            }
        }

        pub fn freeKey(self: *Self, key: keyType) void {
            self.len -= 1;
            self.freeList.appendAssumeCapacity(@intCast(key));
        }

        pub fn clear(self: *Self) void {
            self.len = 0;
            self.freeList.clear();
        }
    };
}
