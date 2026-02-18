const std = @import("std");

fn FindSmallestIntType(number: usize) type {
    return std.math.IntFittingRange(0, number);
}

pub fn CreateMapArray(comptime itemType: type, comptime capacity: u32, comptime keyType: type, comptime keyMax: u32, comptime keyMin: u32) type {
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
        links: [capacity]smallKeyType = .{sentinel} ** capacity,
        items: [capacity]itemType = undefined,

        pub fn upsert(self: *Self, key: keyType, item: itemType) void {
            const castedKey: smallKeyType = @truncate(key - keyMin);

            if (self.keys[castedKey] == sentinel) {
                // Insert
                const index = self.len;
                self.keys[castedKey] = index;
                self.links[index] = castedKey;
                self.items[index] = item;
                self.len += 1;
            } else {
                // Update
                const index = self.keys[castedKey];
                self.items[index] = item;
            }
        }

        pub fn insert(self: *Self, key: keyType, item: itemType) void {
            const castedKey: smallKeyType = @truncate(key - keyMin);
            const index = self.len;
            
            self.keys[castedKey] = index;
            self.links[index] = castedKey;
            self.items[index] = item;
            self.len += 1;
        }

        pub fn update(self: *Self, key: keyType, item: itemType) void {
            const castedKey: smallKeyType = @truncate(key - keyMin);
            const index = self.keys[castedKey];
            self.items[index] = item;
        }

        pub fn appendUnlinked(self: *Self, item: itemType) void {
            self.items[self.len] = item;
            self.links[self.len] = sentinel;
            self.len += 1;
        }

        pub fn link(self: *Self, index: u32, key: keyType) void {
            const castedKey: smallKeyType = @truncate(key - keyMin);
            const oldKey = self.links[index];

            if (oldKey != sentinel) self.keys[oldKey] = sentinel;
            self.keys[castedKey] = @truncate(index);
            self.links[index] = castedKey;
        }

        pub fn unlink(self: *Self, key: keyType) void {
            const castedKey: smallKeyType = @truncate(key - keyMin);
            self.unlinkIndex(self.keys[castedKey]);
        }

        pub fn unlinkIndex(self: *Self, index: u32) void {
            const key = self.links[index];
            if (key != sentinel) {
                self.keys[key] = sentinel;
                self.links[index] = sentinel;
            }
        }

        pub fn clear(self: *Self) void {
            self.len = 0;
            @memset(&self.keys, sentinel);
            @memset(&self.links, sentinel);
        }

        pub fn removeLast(self: *Self) void {
            const key = self.links[self.len - 1];
            if (key != sentinel) self.keys[key] = sentinel;

            self.links[self.len - 1] = sentinel;
            self.len -= 1;
        }

        pub fn remove(self: *Self, key: keyType) void {
            const castedKey: smallKeyType = @truncate(key - keyMin);
            self.removeIndex(self.keys[castedKey]);
        }

        pub fn removeIndex(self: *Self, index: u32) void {
            const keyIndex = self.links[index];
            if (keyIndex != sentinel) self.keys[keyIndex] = sentinel;

            const lastIndex = self.len - 1;
            self.len -= 1;

            if (index != lastIndex) {
                const lastKey = self.links[lastIndex];
                // Move last item to removed position
                self.items[index] = self.items[lastIndex];
                self.links[index] = lastKey;
                // Update key mapping if last item has a key
                if (lastKey != sentinel) self.keys[lastKey] = @truncate(index);
            }
            self.links[lastIndex] = sentinel;
        }

        pub fn swap(self: *Self, key1: keyType, key2: keyType) void {
            const castedKey1: smallKeyType = @truncate(key1 - keyMin);
            const castedKey2: smallKeyType = @truncate(key2 - keyMin);
            self.swapIndices(self.keys[castedKey1], self.keys[castedKey2]);
        }

        pub fn swapIndices(self: *Self, index1: u32, index2: u32) void {
            if (index1 == index2) return;
            const tempItem = self.items[index1];
            self.items[index1] = self.items[index2];
            self.items[index2] = tempItem;

            const tempLink = self.links[index1];
            self.links[index1] = self.links[index2];
            self.links[index2] = tempLink;

            if (self.links[index1] != sentinel) self.keys[self.links[index1]] = @truncate(index1);
            if (self.links[index2] != sentinel) self.keys[self.links[index2]] = @truncate(index2);
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

        pub inline fn isLinked(self: *const Self, index: u32) bool {
            return self.links[index] != sentinel;
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

        pub inline fn getKeyByIndex(self: *const Self, index: u32) u32 {
            return self.links[index] + keyMin;
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
