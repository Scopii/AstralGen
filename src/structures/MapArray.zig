const std = @import("std");

fn FindSmallestIntType(number: usize) type {
    return std.math.IntFittingRange(0, number);
}

pub fn CreateMapArray(comptime elementType: type, comptime size: u32, comptime keyType: type, comptime keyMax: u32, comptime keyMin: u32) type {
    comptime {
        if (keyMax < size) @compileError("MapArray: keyMax must be >= size");
        if (keyMin > keyMax) @compileError("MapArray: keyMax must be > keyMin");
    }
    const elementLimit = size - 1;

    const usedKeyCount = keyMax - keyMin + 1;
    const sentinel = usedKeyCount + 1;
    const smallKeyType = FindSmallestIntType(sentinel);
    const indexType = FindSmallestIntType(size + 1); //

    return struct {
        const Self = @This();
        count: indexType = 0,

        keys: [usedKeyCount]smallKeyType = .{sentinel} ** usedKeyCount,
        links: [size]smallKeyType = .{sentinel} ** size,
        elements: [size]elementType = undefined,

        pub fn set(self: *Self, key: keyType, element: elementType) void {
            const castedKey: smallKeyType = @truncate(key - keyMin);

            if (self.keys[castedKey] == sentinel) {
                const index = self.count;
                self.keys[castedKey] = index;
                self.links[index] = castedKey;
                self.elements[index] = element;
                self.count += 1;
            } else {
                const index = self.keys[castedKey];
                self.elements[index] = element;
            }
        }

        pub fn setMany(self: *Self, keys: []const keyType, elements: []const elementType) void {
            for (keys, elements) |key, element| self.set(key, element);
        }

        pub fn overwriteAtIndex(self: *Self, index: u32, element: elementType) void {
            self.elements[index] = element;
        }

        pub fn append(self: *Self, element: elementType) void {
            self.elements[self.count] = element;
            self.links[self.count] = sentinel;
            self.count += 1;
        }

        pub fn appendMany(self: *Self, elements: []const elementType) void {
            for (elements) |element| self.append(element);
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
            self.unlinkAtIndex(self.keys[castedKey]);
        }

        pub fn unlinkAtIndex(self: *Self, index: u32) void {
            const key = self.links[index];
            if (key != sentinel) {
                self.keys[key] = sentinel;
                self.links[index] = sentinel;
            }
        }

        pub fn clear(self: *Self) void {
            self.count = 0;
            //for (0..usedKeyCount) |i| self.keys[i] = sentinel;
            //for (0..size) |i| self.links[i] = sentinel;
            @memset(&self.keys, sentinel);
            @memset(&self.links, sentinel);
        }

        pub fn removeLast(self: *Self) void {
            const key = self.links[self.count - 1];
            if (key != sentinel) self.keys[key] = sentinel;

            self.links[self.count - 1] = sentinel;
            self.count -= 1;
        }

        pub fn removeMany(self: *Self, number: u32) void {
            for (number) |_| self.removeLast();
        }

        pub fn removeAtKey(self: *Self, key: keyType) void {
            self.removeAtIndex(self.keys[key - keyMin]);
        }

        pub fn removeAtIndex(self: *Self, index: u32) void {
            const keyIndex = self.links[index];
            if (keyIndex != sentinel) self.keys[keyIndex] = sentinel;

            const lastIndex = self.count - 1;
            self.count -= 1;

            if (index != lastIndex) {
                const lastKey = self.links[lastIndex];
                // Move last element to removed position
                self.elements[index] = self.elements[lastIndex];
                self.links[index] = lastKey;
                // Update key mapping if last element has a key
                if (lastKey != sentinel) self.keys[lastKey] = @truncate(index);
            }
            self.links[lastIndex] = sentinel;
        }

        pub fn swapOnlyElement(self: *Self, key1: keyType, key2: keyType) void {
            self.swapOnlyElementAtIndex(self.keys[key1 - keyMin], self.keys[key2 - keyMin]);
        }

        pub fn swapOnlyElementAtIndex(self: *Self, index1: u32, index2: u32) void {
            if (index1 == index2) return;
            const tempElement = self.elements[index1];
            self.elements[index1] = self.elements[index2];
            self.elements[index2] = tempElement;
        }

        pub fn swap(self: *Self, key1: keyType, key2: keyType) void {
            self.swapAtIndex(self.keys[key1 - keyMin], self.keys[key2 - keyMin]);
        }

        pub fn swapAtIndex(self: *Self, index1: u32, index2: u32) void {
            if (index1 == index2) return;
            const tempElement = self.elements[index1];
            self.elements[index1] = self.elements[index2];
            self.elements[index2] = tempElement;

            const tempLink = self.links[index1];
            self.links[index1] = self.links[index2];
            self.links[index2] = tempLink;

            if (self.links[index1] != sentinel) self.keys[self.links[index1]] = @truncate(index1);
            if (self.links[index2] != sentinel) self.keys[self.links[index2]] = @truncate(index2);
        }

        pub fn isKeyUsedAndValid(self: *const Self, key: keyType) bool {
            if (self.isKeyValid(key) == false) return false;
            const castedKey: smallKeyType = @truncate(key - keyMin);
            return self.keys[castedKey] != sentinel;
        }

        pub fn isKeyUsed(self: *const Self, key: keyType) bool {
            const castedKey: smallKeyType = @truncate(key - keyMin);
            return self.keys[castedKey] != sentinel;
        }

        pub inline fn isKeyValid(_: *const Self, key: keyType) bool {
            return key >= keyMin and (key - keyMin) < usedKeyCount;
        }

        pub inline fn isIndexUsed(self: *const Self, index: u32) bool {
            return index < self.count;
        }

        pub inline fn isIndexValid(_: *const Self, index: u32) bool {
            return index <= elementLimit;
        }

        pub inline fn isFull(self: *const Self) bool {
            return self.count >= size;
        }

        pub inline fn isLinked(self: *const Self, index: u32) bool {
            return self.links[index] != sentinel;
        }

        pub inline fn getElements(self: *Self) []elementType {
            return self.elements[0..self.count];
        }

        pub inline fn getElementsArrayPtr(self: *Self) *[size]elementType {
            return &self.elements;
        }

        pub inline fn getUpperKeyLimit(_: *const Self) u32 {
            return keyMax;
        }

        pub inline fn getLowerKeyLimit(_: *const Self) u32 {
            return keyMin;
        }

        pub inline fn getLastValidIndex(_: *const Self) u32 {
            return size - 1;
        }

        pub inline fn getMaximumElements(_: *const Self) u32 {
            return size;
        }

        pub inline fn getPossibleKeyCount(_: *const Self) u32 {
            return usedKeyCount;
        }

        pub inline fn get(self: *const Self, key: keyType) elementType {
            return self.elements[self.keys[(key - keyMin)]];
        }

        pub inline fn getIndex(self: *const Self, key: keyType) smallKeyType {
            return self.keys[(key - keyMin)]; // NOT TESTED YET
        }

        pub inline fn getPtr(self: *Self, key: keyType) *elementType {
            return &self.elements[self.keys[(key - keyMin)]];
        }

        pub inline fn getAtIndex(self: *const Self, index: u32) elementType {
            return self.elements[index];
        }

        pub inline fn getPtrAtIndex(self: *Self, index: u32) *elementType {
            return &self.elements[index];
        }

        pub inline fn getFirst(self: *const Self) elementType {
            return self.elements[0];
        }

        pub inline fn getFirstPtr(self: *Self) *elementType {
            return &self.elements[0];
        }

        pub inline fn getLast(self: *const Self) elementType {
            return self.elements[self.count - 1];
        }

        pub inline fn getLastPtr(self: *Self) *elementType {
            return &self.elements[self.count - 1];
        }

        pub inline fn getNextFreeIndex(self: *const Self) u32 {
            return self.count;
        }

        pub inline fn getCount(self: *const Self) u32 {
            return self.count;
        }

        pub inline fn getUnusedCount(self: *const Self) u32 {
            return size - self.count;
        }
    };
}
