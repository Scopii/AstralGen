const std = @import("std");

/// Creates a MapArray Type with
pub fn CreateMapArray(comptime elementType: type, comptime elementMax: u32, comptime keyType: type, comptime keyMax: u32, comptime keyShift: u32) type {
    comptime {
        if (keyMax < elementMax) {
            @compileError("MapArray: must be >= elementMax");
        }
    }
    const elementLimit = elementMax - 1; // Last Element Array Index
    const keyLimit = keyMax - 1; // Last Key Array Index

    const usedKeyCount = keyMax - keyShift;
    const sentinelValue = usedKeyCount + 1;
    const smallKeyType = FindSmallestIntType(sentinelValue);
    const BitSet = std.bit_set.ArrayBitSet(usize, usedKeyCount);
    const indexType = FindSmallestIntType(elementMax);

    return struct {
        const Self = @This();
        count: indexType = 0,

        bits: BitSet = BitSet.initEmpty(),
        keys: [usedKeyCount]smallKeyType = undefined, //

        links: [elementMax]smallKeyType = .{sentinelValue} ** elementMax,
        elements: [elementMax]elementType = undefined,

        pub fn set(self: *Self, key: keyType, element: elementType) void {
            const castedKey: smallKeyType = @intCast(key - keyShift);

            if (self.isKeyUsed(castedKey) == false) {
                const index = self.count;
                self.bits.setValue(castedKey, true);
                self.keys[castedKey] = index;
                self.links[index] = castedKey;
                self.elements[index] = element;
                self.count += 1;
            } else {
                const index = self.keys[castedKey];
                self.elements[index] = element;
            }
        }

        pub fn setAtIndex(self: *Self, index: u32, element: elementType) void {
            self.elements[index] = element;
        }

        pub fn append(self: *Self, element: elementType) void {
            self.elements[self.count] = element;
            self.links[self.count] = sentinelValue;
            self.count += 1;
        }

        pub fn removeLast(self: *Self) void {
            const key = self.links[self.count - 1];
            if (key != sentinelValue) self.bits.setValue(key, false);
            self.count -= 1;
        }

        pub fn removeAtKey(self: *Self, key: keyType) void {
            self.removeAtIndex(self.keys[key - keyShift]);
        }

        pub fn removeAtIndex(self: *Self, index: u32) void {
            const keyIndex = self.links[index];

            // Clear bit if this element has a key
            if (keyIndex != sentinelValue) self.bits.setValue(keyIndex, false);

            const lastIndex = self.count - 1;
            self.count -= 1;

            if (index != lastIndex) {
                const lastKey = self.links[lastIndex];
                // Move last element to removed position
                self.elements[index] = self.elements[lastIndex];
                self.links[index] = lastKey;
                // Update key mapping ONLY if last element has a key
                if (lastKey != sentinelValue) self.keys[lastKey] = @intCast(index);
            }
        }

        pub fn swapOnlyElement(self: *Self, key1: keyType, key2: keyType) void {
            self.swapOnlyElementAtIndex(self.keys[key1 - keyShift], self.keys[key2 - keyShift]);
        }

        pub fn swapOnlyElementAtIndex(self: *Self, index1: u32, index2: u32) void {
            const tempElement = self.elements[index1];
            self.elements[index1] = self.elements[index2];
            self.elements[index2] = tempElement;
        }

        pub fn swap(self: *Self, key1: keyType, key2: keyType) void {
            self.swapAtIndex(self.keys[key1 - keyShift], self.keys[key2 - keyShift]);
        }

        pub fn swapAtIndex(self: *Self, index1: u32, index2: u32) void {
            const tempElement = self.elements[index1];
            self.elements[index1] = self.elements[index2];
            self.elements[index2] = tempElement;

            const tempLink = self.links[index1];
            self.links[index1] = self.links[index2];
            self.links[index2] = tempLink;

            if (self.links[index1] != sentinelValue) self.keys[self.links[index1]] = @intCast(index1);
            if (self.links[index2] != sentinelValue) self.keys[self.links[index2]] = @intCast(index2);
        }

        pub fn isKeyUsed(self: *Self, key: keyType) bool {
            const castedKey: smallKeyType = @intCast(key - keyShift);
            return self.bits.isSet(castedKey);
        }

        pub fn isKeyUsedAndValid(self: *Self, key: keyType) bool {
            if (self.isKeyValid(key) == false) return false;
            const castedKey: smallKeyType = @intCast(key - keyShift);
            return self.bits.isSet(castedKey);
        }

        pub inline fn isKeyValid(_: *Self, key: keyType) bool {
            return key >= keyShift and (key - keyShift) < usedKeyCount;
        }

        pub inline fn isIndexUsed(self: *Self, index: u32) bool {
            return index < self.count;
        }

        pub inline fn isFull(self: *Self) bool {
            return self.count >= elementMax;
        }

        pub inline fn isIndexValid(_: *Self, index: u32) bool {
            return index <= elementLimit;
        }

        pub inline fn getKeyLimit(_: *Self) u32 {
            return keyLimit;
        }

        pub inline fn getIndexLimit(_: *Self) u32 {
            return elementLimit;
        }

        pub inline fn getMaximumElements(_: *Self) u32 {
            return elementMax;
        }

        pub inline fn getInternalKeyRange(_: *Self) u32 {
            return usedKeyCount;
        }

        pub inline fn getShift(_: *Self) u32 {
            return keyShift;
        }

        pub inline fn getUsedKeyCount(self: *Self) u32 {
            return @intCast(self.bits.count());
        }

        pub inline fn get(self: *Self, key: keyType) elementType {
            return self.elements[self.keys[key - keyShift]];
        }

        pub inline fn getPtr(self: *Self, key: keyType) *elementType {
            return &self.elements[self.keys[key - keyShift]];
        }

        pub inline fn getAtIndex(self: *Self, index: u32) elementType {
            return self.elements[index];
        }

        pub inline fn getPtrAtIndex(self: *Self, index: u32) *elementType {
            return &self.elements[index];
        }

        pub inline fn getFirst(self: *Self) elementType {
            return self.elements[0];
        }

        pub inline fn getFirstPtr(self: *Self) *elementType {
            return &self.elements[0];
        }

        pub inline fn getLast(self: *Self) elementType {
            return self.elements[self.count - 1];
        }

        pub inline fn getLastPtr(self: *Self) *elementType {
            return &self.elements[self.count - 1];
        }

        pub inline fn getNextFreeIndex(self: *Self) u32 {
            return self.count;
        }

        pub inline fn getCount(self: *Self) u32 {
            return self.count;
        }
    };
}

fn FindSmallestIntType(number: usize) type {
    return std.math.IntFittingRange(0, number - 1);
}
