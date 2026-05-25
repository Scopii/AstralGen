const std = @import("std");

pub fn FixedList(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        buffer: [capacity]T = undefined,
        len: usize = 0,

        pub fn init() Self {
            return .{ .len = 0 };
        }

        pub fn appendSlice(self: *Self, items: []const T) !void {
            if (self.len + items.len > capacity) return error.ListFull;
            @memcpy(self.buffer[self.len .. items.len + self.len], items);
            self.len += items.len;
        }

        pub fn appendSliceAssumeCapacity(self: *Self, items: []const T) void {
            std.debug.assert(self.len + items.len <= capacity);
            @memcpy(self.buffer[self.len .. self.len + items.len], items);
            self.len += items.len;
        }

        pub fn append(self: *Self, item: T) !void {
            if (self.len >= capacity) return error.ListFull;
            self.buffer[self.len] = item;
            self.len += 1;
        }

        pub fn appendReturnPtr(self: *Self, item: T) !*T {
            if (self.len >= capacity) return error.ListFull;
            const ptr = &self.buffer[self.len];
            ptr.* = item;
            self.len += 1;
            return ptr;
        }

        pub fn appendAssumeCapacity(self: *Self, item: T) void {
            std.debug.assert(self.len < capacity);
            self.buffer[self.len] = item;
            self.len += 1;
        }

        pub fn slice(self: *Self) []T {
            return self.buffer[0..self.len];
        }

        pub fn constSlice(self: *const Self) []const T {
            return self.buffer[0..self.len];
        }

        pub fn clear(self: *Self) void {
            self.len = 0;
        }

        pub fn swapRemove(self: *Self, index: u32) void {
            std.debug.assert(index < self.len);
            self.len -= 1;
            if (index != self.len) self.buffer[index] = self.buffer[self.len];
        }

        pub fn swapRemoveReturn(self: *Self, index: u32) T {
            std.debug.assert(index < self.len);
            const removed = self.buffer[index];
            self.len -= 1;
            if (index != self.len) self.buffer[index] = self.buffer[self.len];
            return removed;
        }

        pub fn selectionSort(self: *Self, greaterFunction: fn (anytype, anytype) bool) void {
            var i: u32 = 0;
            while (i < self.len) : (i += 1) {
                var min = i;
                var j = i + 1;
                while (j < self.len) : (j += 1) {
                    if (greaterFunction(self.buffer[min], self.buffer[j])) min = j; // find smallest in the rest
                }
                if (min != i) self.swap(i, min);
            }
        }

        pub fn swap(self: *Self, index1: u32, index2: u32) void {
            std.debug.assert(index1 < self.len and index2 < self.len);
            const copy1 = self.buffer[index1];
            self.buffer[index1] = self.buffer[index2];
            self.buffer[index2] = copy1;
        }

        pub fn pop(self: *Self) ?T {
            if (self.len == 0) return null;
            self.len -= 1;
            return self.buffer[self.len];
        }
    };
}
