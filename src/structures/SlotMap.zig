const std = @import("std");

fn FindSmallestIntType(number: usize) type {
    return std.math.IntFittingRange(0, number);
}

pub fn SlotMap(comptime itemType: type, comptime capacity: u32, comptime keyType: type, comptime keyMax: u32, comptime keyMin: u32) type {
    comptime {
        if (keyMax < capacity) @compileError("MapArray: keyMax must be >= size");
        if (keyMin > keyMax) @compileError("MapArray: keyMax must be > keyMin");
    }

    const keyRange = keyMax - keyMin + 1;
    const sentinel = keyRange + 1;
    const smallKeyType = FindSmallestIntType(sentinel);
    const indexType = FindSmallestIntType(capacity + 1);

    return struct {
        const Self = @This();
        len: indexType = 0,

        keys: [keyRange]smallKeyType = .{sentinel} ** keyRange,
        items: [capacity]itemType = undefined,

        pub fn upsert(self: *Self, key: keyType, item: itemType) void {
            const castedKey: smallKeyType = @truncate(key - keyMin);

            if (self.keys[castedKey] == sentinel) {
                // Insert
                const index = self.len;
                self.keys[castedKey] = index;
                self.items[index] = item;
                self.len += 1;
            } else {
                // Update
                const index = self.keys[castedKey];
                self.items[index] = item;
            }
        }

        // Slot Map Functions (Changed in LinkedMap):

        pub fn swap(self: *Self, key1: keyType, key2: keyType) void {
            const castedKey1: smallKeyType = @truncate(key1 - keyMin);
            const castedKey2: smallKeyType = @truncate(key2 - keyMin);

            const index1 = self.keys[castedKey1];
            self.keys[castedKey1] = self.keys[castedKey2];
            self.keys[castedKey2] = index1;
        }

        pub fn link(self: *Self, index: u32, key: keyType) void {
            const castedKey: smallKeyType = @truncate(key - keyMin);
            self.keys[castedKey] = @truncate(index);
        }

        pub fn unlink(self: *Self, key: keyType) void {
            self.keys[@as(usize, @truncate(key - keyMin))] = sentinel;
        }

        // Slot Map Base Functionality:

        pub fn insert(self: *Self, key: keyType, item: itemType) void {
            const castedKey: smallKeyType = @truncate(key - keyMin);
            std.debug.assert(self.keys[castedKey] == sentinel);
            const index = self.len;

            self.keys[castedKey] = index;
            self.items[index] = item;
            self.len += 1;
        }

        pub fn clear(self: *Self) void {
            self.len = 0;
            @memset(&self.keys, sentinel);
        }

        pub fn append(self: *Self, item: itemType) void {
            self.items[self.len] = item;
            self.len += 1;
        }

        // Direct Function Mappings:

        pub fn update(self: *Self, key: keyType, item: itemType) void {
            const castedKey: smallKeyType = @truncate(key - keyMin);
            std.debug.assert(self.keys[castedKey] != sentinel);
            const index = self.keys[castedKey];
            self.items[index] = item;
        }

        pub fn isKeyUsed(self: *const Self, key: keyType) bool {
            const castedKey: smallKeyType = @truncate(key - keyMin);
            return self.keys[castedKey] != sentinel;
        }

        pub inline fn isKeyValid(_: *const Self, key: keyType) bool {
            return key >= keyMin and (key - keyMin) < keyRange;
        }

        pub inline fn isIndexUsed(self: *const Self, index: u32) bool {
            return index < self.len;
        }

        pub inline fn isIndexValid(_: *const Self, index: u32) bool {
            return index < capacity;
        }

        pub inline fn isFull(self: *const Self) bool {
            return self.len >= capacity;
        }

        pub inline fn getItems(self: *Self) []itemType {
            return self.items[0..self.len];
        }

        pub inline fn getKeyMax(_: *const Self) u32 {
            return keyMax;
        }

        pub inline fn getKeyMin(_: *const Self) u32 {
            return keyMin;
        }

        pub inline fn getCapacity(_: *const Self) u32 {
            return capacity;
        }

        pub inline fn getByKey(self: *const Self, key: keyType) itemType {
            return self.items[self.keys[(key - keyMin)]];
        }

        pub inline fn getIndexByKey(self: *const Self, key: keyType) smallKeyType {
            return self.keys[(key - keyMin)];
        }

        pub inline fn getPtrByKey(self: *Self, key: keyType) *itemType {
            return &self.items[self.keys[(key - keyMin)]];
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
