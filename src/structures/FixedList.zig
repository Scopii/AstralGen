const std = @import("std");

pub fn FixedList(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        buffer: [capacity]T = undefined,
        len: usize = 0,

        pub fn init() Self {
            return .{ .len = 0 };
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

        pub fn pop(self: *Self) ?T {
            if (self.len == 0) return null;
            self.len -= 1;
            return self.buffer[self.len];
        }
    };
}
