const std = @import("std");

pub fn RingList(comptime ItemType: type, comptime capacity: usize) type {
    if (capacity == 0) @compileError("RingList capacity must be > 0"); // fail at compile time, not at runtime

    return struct {
        const Self = @This();
        const IntFittingRange: type = std.math.IntFittingRange(0, capacity);

        buffer: [capacity]ItemType = undefined,
        start: IntFittingRange = 0,
        len: IntFittingRange = 0,

        fn wrap(value: usize) IntFittingRange {
            return @intCast(value % capacity);
        }

        fn nextSlot(self: *const Self) ?IntFittingRange {
            if (self.len >= capacity) return null;
            return wrap(@as(usize, self.start) + self.len);
        }

        fn previousSlot(self: *const Self) ?IntFittingRange {
            if (self.len >= capacity) return null;
            return if (self.start == 0) capacity - 1 else self.start - 1;
        }

        fn getEnd(self: *const Self) IntFittingRange {
            return wrap(@as(usize, self.start) + self.len - 1);
        }

        pub fn getLength(self: *const Self) IntFittingRange {
            return self.len;
        }

        pub fn isFull(self: *const Self) bool {
            return self.len == capacity;
        }

        pub fn appendLast(self: *Self, item: ItemType) !void {
            if (self.nextSlot()) |freeSlot| {
                self.buffer[freeSlot] = item;
                self.len += 1;
            } else return error.NoFreeSlotInRingList;
        }

        pub fn appendFirst(self: *Self, item: ItemType) !void {
            if (self.previousSlot()) |freeSlot| {
                self.buffer[freeSlot] = item;
                self.start = freeSlot;
                self.len += 1;
            } else return error.NoFreeSlotInRingList;
        }

        pub fn getFirstItem(self: *const Self) ?ItemType {
            return if (self.len == 0) null else self.buffer[self.start];
        }

        pub fn getLastItem(self: *const Self) ?ItemType {
            return if (self.len == 0) null else self.buffer[self.getEnd()];
        }

        pub fn removeFirstItem(self: *Self) ?ItemType {
            if (self.getFirstItem()) |firstItem| {
                self.start = if (self.start == capacity - 1) 0 else self.start + 1;
                self.len -= 1;
                return firstItem;
            } else return null;
        }

        pub fn removeLastItem(self: *Self) ?ItemType {
            if (self.getLastItem()) |lastItem| {
                self.len -= 1;
                return lastItem;
            } else return null;
        }

        pub fn clear(self: *Self) void {
            self.start = 0;
            self.len = 0;
        }
    };
}
