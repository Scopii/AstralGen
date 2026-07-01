const std = @import("std");
const FixedList = @import("FixedList.zig").FixedList;

fn FindSmallestIntType(number: usize) type {
    return std.math.IntFittingRange(0, number);
}

pub fn KeyPool(
    comptime keyType: type,
    comptime capacity: u32,
) type {
    const smallKeyType = FindSmallestIntType(capacity);
    const indexType = FindSmallestIntType(capacity + 1);

    return struct {
        const Self = @This();
        nextId: indexType = 0,
        freeList: FixedList(smallKeyType, capacity) = .{},

        pub fn reserveKey(self: *Self) keyType {
            std.debug.assert(self.nextId < capacity or self.freeList.len > 0);
            if (self.freeList.pop()) |key| {
                return @intCast(key);
            }
            const key = self.nextId;
            self.nextId += 1;
            return @intCast(key);
        }

        pub fn isFull(self: *const Self) bool {
            return self.nextId >= capacity and self.freeList.len == 0;
        }

        pub fn tryReserveKey(self: *Self) ?keyType {
            if (self.isFull()) return null;
            return self.reserveKey();
        }

        pub fn freeKey(self: *Self, key: keyType) void {
            std.debug.assert(@as(u32, @intCast(key)) < capacity);
            self.freeList.appendAssumeCapacity(@intCast(key));
        }

        pub fn clear(self: *Self) void {
            self.nextId = 0;
            self.freeList.clear();
        }
    };
}