const std = @import("std");
const FixedList = @import("FixedList.zig").FixedList;

fn FindSmallestIntType(number: usize) type {
    return std.math.IntFittingRange(0, number);
}

pub fn SlotMap(comptime itemType: type, comptime capacity: u32, comptime keyType: type) type {
    const keyRange = capacity + 1;
    const sentinel = keyRange + 1;
    const smallKeyType = FindSmallestIntType(sentinel);
    const indexType = FindSmallestIntType(capacity + 1);

    return struct {
        const Self = @This();
        len: indexType = 0,

        keys: [keyRange]smallKeyType = .{sentinel} ** keyRange,
        items: [capacity]itemType = undefined,
        links: [capacity]smallKeyType = undefined,
        freeList: FixedList(smallKeyType, capacity) = .{},

        pub fn insert(self: *Self, item: itemType) keyType {
            std.debug.assert(self.isFull() == false);
            const keyOrNull: ?smallKeyType = self.freeList.pop();

            if (keyOrNull) |key| {
                const index = self.len;
                self.keys[key] = @intCast(index);
                self.links[index] = key;
                self.items[index] = item;
                self.len += 1;
                return @intCast(key);
            } else {
                const indexAndKey = self.len;
                self.keys[indexAndKey] = @intCast(indexAndKey);
                self.links[indexAndKey] = @intCast(indexAndKey);
                self.items[indexAndKey] = item;
                self.len += 1;
                return @intCast(indexAndKey);
            }
        }

        pub fn swapRemove(self: *Self, key: keyType) void {
            const index: smallKeyType = self.keys[key];
            const last: smallKeyType = @intCast(self.len - 1);

            self.keys[key] = sentinel;

            if (index != last) {
                const lastKey = self.links[last];
                self.items[index] = self.items[last];
                self.links[index] = lastKey;
                self.keys[lastKey] = @intCast(index);
            }
            self.len -= 1;
            self.freeList.appendAssumeCapacity(@intCast(key));
        }

        pub fn clear(self: *Self) void {
            self.len = 0;
            self.freeList.clear();
            @memset(&self.keys, sentinel);
        }

        pub fn isKeyUsed(self: *const Self, key: keyType) bool {
            const castedKey: smallKeyType = @intCast(key);
            return self.keys[castedKey] != sentinel;
        }

        pub inline fn isFull(self: *const Self) bool {
            return self.len >= capacity;
        }

        pub inline fn getItems(self: *Self) []itemType {
            return self.items[0..self.len];
        }

        pub inline fn getConstItems(self: *const Self) []const itemType {
            return self.items[0..self.len];
        }

        pub inline fn getCapacity(_: *const Self) u32 {
            return capacity;
        }

        pub inline fn getByKey(self: *const Self, key: keyType) itemType {
            return self.items[self.keys[key]];
        }

        pub inline fn getIndexByKey(self: *const Self, key: keyType) smallKeyType {
            return self.keys[(key)];
        }

        pub inline fn getPtrByKey(self: *Self, key: keyType) *itemType {
            return &self.items[self.keys[(key)]];
        }

        pub inline fn getByIndex(self: *const Self, index: u32) itemType {
            return self.items[index];
        }

        pub inline fn getPtrByIndex(self: *Self, index: u32) *itemType {
            return &self.items[index];
        }

        pub inline fn getFirst(self: *const Self) itemType {
            return self.items[0];
        }

        pub inline fn getFirstPtr(self: *Self) *itemType {
            return &self.items[0];
        }

        pub inline fn getLast(self: *const Self) itemType {
            return self.items[self.len - 1];
        }

        pub inline fn getLastPtr(self: *Self) *itemType {
            return &self.items[self.len - 1];
        }

        pub inline fn getLength(self: *const Self) u32 {
            return self.len;
        }
    };
}
