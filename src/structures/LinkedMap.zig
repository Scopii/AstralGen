const std = @import("std");
const SlotMap = @import("SlotMap.zig").SlotMap;

fn FindSmallestIntType(number: usize) type {
    return std.math.IntFittingRange(0, number);
}

pub fn LinkedMap(comptime itemType: type, comptime capacity: u32, comptime keyType: type, comptime keyMax: u32, comptime keyMin: u32) type {
    comptime {
        if (keyMax < capacity) @compileError("MapArray: keyMax must be >= size");
        if (keyMin > keyMax) @compileError("MapArray: keyMax must be > keyMin");
    }

    const keyRange = keyMax - keyMin + 1;
    const sentinel = keyRange + 1;
    const smallKeyType = FindSmallestIntType(sentinel);

    return struct {
        const Self = @This();

        slotMap: SlotMap(itemType, capacity, keyType, keyMax, keyMin) = .{},
        links: [capacity]smallKeyType = .{sentinel} ** capacity,

        pub fn upsert(self: *Self, key: keyType, item: itemType) void {
            if (self.isKeyUsed(key) == false) {
                self.insert(key, item);
            } else {
                self.update(key, item);
            }
        }

        // Functions with Changed logic:

        pub fn swap(self: *Self, key1: keyType, key2: keyType) void {
            const castedKey1: smallKeyType = @truncate(key1 - keyMin);
            const castedKey2: smallKeyType = @truncate(key2 - keyMin);
            std.debug.assert(self.slotMap.keys[castedKey1] != sentinel);
            std.debug.assert(self.slotMap.keys[castedKey2] != sentinel);
            self.swapIndices(@intCast(self.slotMap.keys[castedKey1]), @intCast(self.slotMap.keys[castedKey2]));
        }

        pub fn link(self: *Self, index: u32, key: keyType) void {
            const castedKey: smallKeyType = @truncate(key - keyMin);
            const oldKey = self.links[index];

            if (oldKey != sentinel) self.slotMap.keys[oldKey] = sentinel;
            self.slotMap.keys[castedKey] = @truncate(index);
            self.links[index] = castedKey;
        }

        pub fn unlink(self: *Self, key: keyType) void {
            const castedKey: smallKeyType = @truncate(key - keyMin);
            const index = self.slotMap.keys[castedKey];
            if (index == sentinel) return;
            self.unlinkIndex(@intCast(index));
        }

        pub fn remove(self: *Self, key: keyType) void {
            self.removeIndex(@intCast(self.getIndexByKey(key)));
        }

        pub inline fn isLinked(self: *const Self, index: u32) bool {
            return self.links[index] != sentinel;
        }

        // Additional Logic + SlotMap Functionality:

        pub fn insert(self: *Self, key: keyType, item: itemType) void {
            const index = self.slotMap.len;
            self.slotMap.insert(key, item);
            self.links[index] = @truncate(key - keyMin);
        }

        pub fn clear(self: *Self) void {
            self.slotMap.clear();
            @memset(&self.links, sentinel);
        }

        pub fn appendUnlinked(self: *Self, item: itemType) void {
            self.slotMap.append(item);
        }

        // Exclusive Linked Map Functions:

        pub fn removeLast(self: *Self) void {
            const key = self.links[self.slotMap.len - 1];
            if (key != sentinel) self.slotMap.keys[key] = sentinel;

            self.links[self.slotMap.len - 1] = sentinel;
            self.slotMap.len -= 1;
        }

        pub inline fn getKeyByIndex(self: *const Self, index: u32) u32 {
            std.debug.assert(self.isLinked(index));
            return self.links[index] + keyMin;
        }

        pub fn swapIndices(self: *Self, index1: u32, index2: u32) void {
            if (index1 == index2) return;
            const tempItem = self.slotMap.items[index1];
            self.slotMap.items[index1] = self.slotMap.items[index2];
            self.slotMap.items[index2] = tempItem;

            const tempLink = self.links[index1];
            self.links[index1] = self.links[index2];
            self.links[index2] = tempLink;

            if (self.links[index1] != sentinel) self.slotMap.keys[self.links[index1]] = @truncate(index1);
            if (self.links[index2] != sentinel) self.slotMap.keys[self.links[index2]] = @truncate(index2);
        }

        pub fn removeIndex(self: *Self, index: u32) void {
            const keyIndex = self.links[index];
            if (keyIndex != sentinel) self.slotMap.keys[keyIndex] = sentinel;

            const lastIndex = self.slotMap.len - 1;
            self.slotMap.len -= 1;

            if (index != lastIndex) {
                const lastKey = self.links[lastIndex];
                // Move last item to removed position
                self.slotMap.items[index] = self.slotMap.items[lastIndex];
                self.links[index] = lastKey;
                // Update key mapping if last item has a key
                if (lastKey != sentinel) self.slotMap.keys[lastKey] = @truncate(index);
            }
            self.links[lastIndex] = sentinel;
        }

        pub fn unlinkIndex(self: *Self, index: u32) void {
            const key = self.links[index];
            if (key != sentinel) {
                self.slotMap.keys[key] = sentinel;
                self.links[index] = sentinel;
            }
        }

        // Direct Function Mappings:

        pub fn update(self: *Self, key: keyType, item: itemType) void {
            self.slotMap.update(key, item);
        }

        pub fn isKeyUsed(self: *const Self, key: keyType) bool {
            return self.slotMap.isKeyUsed(key);
        }

        pub inline fn isKeyValid(self: *const Self, key: keyType) bool {
            return self.slotMap.isKeyValid(key);
        }

        pub inline fn isIndexUsed(self: *const Self, index: u32) bool {
            return self.slotMap.isIndexUsed(index);
        }

        pub inline fn isIndexValid(self: *const Self, index: u32) bool {
            return self.slotMap.isIndexValid(index);
        }

        pub inline fn isFull(self: *const Self) bool {
            return self.slotMap.isFull();
        }

        pub inline fn getItems(self: *Self) []itemType {
            return self.slotMap.getItems();
        }

        pub inline fn getKeyMax(self: *const Self) u32 {
            return self.slotMap.getKeyMax();
        }

        pub inline fn getKeyMin(self: *const Self) u32 {
            return self.slotMap.getKeyMin();
        }

        pub inline fn getCapacity(self: *const Self) u32 {
            return self.slotMap.getCapacity();
        }

        pub inline fn getByKey(self: *const Self, key: keyType) itemType {
            return self.slotMap.getByKey(key);
        }

        pub inline fn getIndexByKey(self: *const Self, key: keyType) smallKeyType {
            return self.slotMap.getIndexByKey(key);
        }

        pub inline fn getPtrByKey(self: *Self, key: keyType) *itemType {
            return self.slotMap.getPtrByKey(key);
        }

        pub inline fn getByIndex(self: *const Self, index: u32) itemType {
            return self.slotMap.getByIndex(index);
        }

        pub inline fn getPtrByIndex(self: *Self, index: u32) *itemType {
            return self.slotMap.getPtrByIndex(index);
        }

        pub inline fn getFirst(self: *const Self) itemType {
            return self.slotMap.getFirst();
        }

        pub inline fn getFirstPtr(self: *Self) *itemType {
            return self.slotMap.getFirstPtr();
        }

        pub inline fn getLast(self: *const Self) itemType {
            return self.slotMap.getLast();
        }

        pub inline fn getLastPtr(self: *Self) *itemType {
            return self.slotMap.getLastPtr();
        }

        pub inline fn getLength(self: *const Self) u32 {
            return self.slotMap.getLength();
        }
    };
}
