const std = @import("std");

/// Creates a MapArray Type which links a sparse array of keys and a dense array of any type bidirectionally.
/// (This is more performant than a hash map and does not have hash collisions at the cost of more memory)
///
/// - For performance/awareness reasons all operations manipulating the MapArray DO NOT CHECK VALIDITY of indices, keys, elements or links!
///     (can still be done if wished by using the internally provided "is*" bool and getter functions)
/// - ALL operations are O(1) the only exception to this is getUsedKeyCount()
/// - removeAtKey() and removeAtIndex() replace the deleted element with the last element
/// - Keys are validated using an ArrayBitSet from the std library to keep data packed
/// - Elements can be added using a key for lookup using the set() function
/// - Elements added using setAtIndex() or append() will not allow access via key and are not internally linked to a key yet
///     (can still be linked later using the link() function)
/// - The MapArray is fully stack allocated and automatically creates internal types for minimal memory footprint
///
/// @param elementType: type, The type of elements to store
/// @param size: u32, Maximum number of elements that can be stored
/// @param keyType: type, The type of sparse keys (must be an unsigned integer type)
/// @param keyMax: u32, Maximum value a key can have (must be >= size)
/// @param keyMin: u32, Minimum value a key can have
///
/// example usage:
/// const MyMapArray = CreateMapArray(Vec4, 1000, u32, 99999, 9999);
/// var arr = MyMapArray{};
/// arr.set(100, 42);
/// arr.append(99);
///
/// *Hint: This can also be used as a general Map storing Indices for multiple Arrays by storing an unsigned integer type as elementType!*
/// *Hint2: It is strongly adviced to keep size, keyMax and keyMin small, higher values can flood memory very quickly!
///  (sizeOf(MapArray) = (1 bit keyRange) + (keyType keyRange) + (keyType size) + (elements size)*
///
/// implementation details:
/// - elementLimit: Last elements array Index
/// - keyLimit: Last keys array index
/// - usedKeyCount: Number of keys within the valid range of min and max
/// - smallKeyType: Smallest possible unsigned integer type that can store usedKeyCount + 1 (sentinelValue)
/// - BitSet: The Type used for the key validation array
/// - indexType: Smallest possible unsigned integer type that can store the number of Elements
///
/// - key: Used as keys array index,
/// - index: Used as index for the links and elements arrays
///
/// - count: Number of elements stored, also describes next available index;
/// - bits: The BitSet used to check which keys are used
/// - keys: The sparse Array of index values for the links and elements arrays
/// - elements: The dense array of elements
///
///
pub fn CreateMapArray(comptime elementType: type, comptime size: u32, comptime keyType: type, comptime keyMax: u32, comptime keyMin: u32) type {
    comptime {
        if (keyMax < size) @compileError("MapArray: keyMax must be >= size");
        if (keyMin > keyMax) @compileError("MapArray: keyMax must be > keyMin");
    }
    const elementLimit = size - 1;

    const usedKeyCount = keyMax - keyMin + 1;
    const sentinel = usedKeyCount + 1;
    const smallKeyType = FindSmallestIntType(sentinel);
    const BitSet = std.bit_set.ArrayBitSet(usize, usedKeyCount);
    const indexType = FindSmallestIntType(size + 1); //

    return struct {
        const Self = @This();
        count: indexType = 0,

        bits: BitSet = BitSet.initEmpty(),
        keys: [usedKeyCount]smallKeyType = undefined,

        links: [size]smallKeyType = .{sentinel} ** size,
        elements: [size]elementType = undefined,

        pub fn set(self: *Self, key: keyType, element: elementType) void {
            const castedKey: smallKeyType = @intCast(key - keyMin);

            if (self.isKeyUsed(key) == false) {
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
            const castedKey: smallKeyType = @intCast(key - keyMin);
            const oldKey = self.links[index];

            if (oldKey != sentinel) {
                self.bits.setValue(oldKey, false);
                self.keys[oldKey] = sentinel;
            }
            self.bits.setValue(castedKey, true);
            self.keys[castedKey] = @intCast(index);
            self.links[index] = castedKey;
        }

        pub fn unlink(self: *Self, key: keyType) void {
            const castedKey: smallKeyType = @intCast(key - keyMin);
            self.unlinkAtIndex(self.keys[castedKey]);
        }

        pub fn unlinkAtIndex(self: *Self, index: u32) void {
            const key = self.links[index];
            if (key != sentinel) {
                self.bits.setValue(key, false);
                self.keys[key] = sentinel;
                self.links[index] = sentinel;
            }
        }

        pub fn clear(self: *Self) void {
            self.count = 0;
            self.bits = BitSet.initEmpty();
            for (0..size) |i| self.links[i] = sentinel;
        }

        pub fn removeLast(self: *Self) void {
            const key = self.links[self.count - 1];
            if (key != sentinel) {
                self.bits.setValue(key, false);
                self.keys[key] = sentinel;
            }
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
            if (keyIndex != sentinel) {
                self.bits.setValue(keyIndex, false);
                self.keys[keyIndex] = sentinel;
            }

            const lastIndex = self.count - 1;
            self.count -= 1;

            if (index != lastIndex) {
                const lastKey = self.links[lastIndex];
                // Move last element to removed position
                self.elements[index] = self.elements[lastIndex];
                self.links[index] = lastKey;
                // Update key mapping if last element has a key
                if (lastKey != sentinel) self.keys[lastKey] = @intCast(index);
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

            if (self.links[index1] != sentinel) self.keys[self.links[index1]] = @intCast(index1);
            if (self.links[index2] != sentinel) self.keys[self.links[index2]] = @intCast(index2);
        }

        pub fn isKeyUsedAndValid(self: *Self, key: keyType) bool {
            if (self.isKeyValid(key) == false) return false;
            const castedKey: smallKeyType = @intCast(key - keyMin);
            return self.bits.isSet(castedKey);
        }

        pub fn isKeyUsed(self: *Self, key: keyType) bool {
            const castedKey: smallKeyType = @intCast(key - keyMin);
            return self.bits.isSet(castedKey);
        }

        pub inline fn isKeyValid(_: *Self, key: keyType) bool {
            return key >= keyMin and (key - keyMin) < usedKeyCount;
        }

        pub inline fn isIndexUsed(self: *Self, index: u32) bool {
            return index < self.count;
        }

        pub inline fn isIndexValid(_: *Self, index: u32) bool {
            return index <= elementLimit;
        }

        pub inline fn isFull(self: *Self) bool {
            return self.count >= size;
        }

        pub inline fn isLinked(self: *Self, index: u32) bool {
            return self.links[index] != sentinel;
        }

        pub inline fn getElements(self: *Self) []elementType {
            return self.elements[0..self.count];
        }

        pub inline fn getElementsArrayPtr(self: *Self) *[size]elementType {
            return &self.elements;
        }

        pub inline fn getUpperKeyLimit(_: *Self) u32 {
            return keyMax;
        }

        pub inline fn getLowerKeyLimit(_: *Self) u32 {
            return keyMin;
        }

        pub inline fn getLastValidIndex(_: *Self) u32 {
            return size - 1;
        }

        pub inline fn getMaximumElements(_: *Self) u32 {
            return size;
        }

        pub inline fn getPossibleKeyCount(_: *Self) u32 {
            return usedKeyCount;
        }

        pub inline fn get(self: *Self, key: keyType) elementType {
            return self.elements[self.keys[key - keyMin]];
        }

        pub inline fn getPtr(self: *Self, key: keyType) *elementType {
            return &self.elements[self.keys[key - keyMin]];
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

        pub inline fn getUnusedCount(self: *Self) u32 {
            return size - self.count;
        }
    };
}

fn FindSmallestIntType(number: usize) type {
    return std.math.IntFittingRange(0, number - 1);
}

const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;

test "MapArrayTest" {
    const elementType = u32;
    const size = 5;
    const keyType = u16;
    const keyMax = 99;
    const keyMin = 10;

    const TestMapArray = CreateMapArray(elementType, size, keyType, keyMax, keyMin);
    var arr = TestMapArray{};

    // Validations
    try expect(arr.isKeyUsed(keyMin) == false);
    try expect(arr.isKeyUsed(keyMax) == false);

    try expect(arr.isKeyValid(keyMin - 1) == false);
    try expect(arr.isKeyValid(keyMin) == true);
    try expect(arr.isKeyValid(keyMax) == true);
    try expect(arr.isKeyValid(keyMax + 1) == false);

    try expectEqual(keyMax, arr.getUpperKeyLimit());
    try expectEqual(keyMin, arr.getLowerKeyLimit());

    try expectEqual(size - 1, arr.getLastValidIndex());
    try expectEqual(size, arr.getMaximumElements());

    try expectEqual(arr.getPossibleKeyCount(), keyMax - keyMin + 1); // because its inclusive
    try expectEqual(arr.getNextFreeIndex(), 0);
    try expectEqual(arr.getUnusedCount(), size);

    try expect(arr.isKeyUsedAndValid(keyMin - 1) == false);
    try expect(arr.isKeyUsedAndValid(keyMin) == false);
    try expect(arr.isKeyUsedAndValid(keyMax) == false);
    try expect(arr.isKeyUsedAndValid(keyMax + 1) == false);

    try expect(arr.isIndexUsed(0) == false);
    try expect(arr.isIndexUsed(1) == false);
    try expect(arr.isIndexUsed(size) == false);

    try expect(arr.isIndexValid(0) == true);
    try expect(arr.isIndexValid(size - 1) == true);
    try expect(arr.isIndexValid(size) == false);
    try expect(arr.isIndexValid(size + 1) == false);

    try expect(arr.isLinked(0) == false);
    try expect(arr.isLinked(size - 1) == false);

    try expect(arr.isFull() == false);

    try expect(arr.getElements().len == 0);
    try expect(arr.getElementsArrayPtr() == &arr.elements);

    // check if all Keys and Links have reserved Sentinel Value
    for (arr.links) |link| try expectEqual(link, keyMax - keyMin + 2); // one for sentinel and one for index being inclusive
    try expectEqual(0, arr.getCount());

    const element1 = 42;
    const element2 = 333;
    const element3 = 1234;
    const key1 = 84;
    const key2 = 89;
    const key3 = 66;

    // Validations before first object
    try expect(arr.isKeyUsed(key1) == false);
    try expect(arr.isKeyUsed(key2) == false);

    try expect(arr.isKeyValid(key1) == true);
    try expect(arr.isKeyValid(key2) == true);

    try expect(arr.isKeyUsedAndValid(key1) == false);
    try expect(arr.isKeyUsedAndValid(key2) == false);

    try expect(arr.isLinked(0) == false);
    try expect(arr.isLinked(1) == false);

    // set
    arr.set(key1, element1);
    try expectEqual(element1, arr.get(key1));
    try expectEqual(1, arr.getCount());
    try expect(arr.isKeyUsed(key1) == true);

    try expect(arr.getElements().len == 1);
    try expectEqual(arr.getNextFreeIndex(), 1);
    try expectEqual(arr.getUnusedCount(), size - 1);

    // Validations after first object
    try expect(arr.isKeyUsed(key1) == true);
    try expect(arr.isKeyValid(key1) == true);
    try expect(arr.isKeyUsedAndValid(key1) == true);

    try expect(arr.isIndexUsed(0) == true);
    try expect(arr.isIndexUsed(1) == false);
    try expect(arr.isIndexUsed(size) == false);

    try expect(arr.isLinked(0) == true);
    try expect(arr.isLinked(1) == false);

    try expect(arr.get(key1) == element1);
    try expect(arr.getAtIndex(0) == element1);
    try expect(arr.getFirst() == arr.getAtIndex(0));

    // set while key is already used
    arr.set(key1, element2);
    try expectEqual(1, arr.getCount());
    try expect(arr.isKeyUsed(key1) == true);

    try expect(arr.getElements().len == 1);
    try expectEqual(arr.getNextFreeIndex(), 1);
    try expectEqual(arr.getUnusedCount(), size - 1);

    // Validation after second object (stored 1)
    try expect(arr.isIndexUsed(0) == true);
    try expect(arr.isIndexUsed(1) == false);

    try expect(arr.isLinked(0) == true);
    try expect(arr.isLinked(1) == false);

    try expect(arr.get(key1) == element2);
    try expect(arr.getPtr(key1).* == element2);
    try expect(arr.getAtIndex(0) == element2);
    try expect(arr.getPtrAtIndex(0).* == arr.getAtIndex(0));
    try expect(arr.getFirst() == arr.getAtIndex(0));
    try expect(arr.getFirst() == arr.getLast());
    try expect(arr.getFirst() == arr.getLast());
    try expect(arr.getFirstPtr() == arr.getLastPtr());

    // setMany with 1 new key
    try expect(arr.isKeyUsed(key2) == false);
    arr.setMany(&.{ key1, key2 }, &.{ element1, element2 });
    try expectEqual(2, arr.getCount());
    try expect(arr.isKeyUsed(key2) == true);

    try expect(arr.get(key1) == element1);
    try expect(arr.getPtr(key1).* == element1);
    try expect(arr.getAtIndex(0) == element1);

    try expect(arr.get(key2) == element2);
    try expect(arr.getPtr(key2).* == element2);
    try expect(arr.getAtIndex(1) == element2);

    try expect(arr.getFirst() == arr.getAtIndex(0));
    try expect(arr.getFirst() == arr.getFirstPtr().*);
    try expect(arr.getFirst() != arr.getAtIndex(1));
    try expect(arr.getFirst() != arr.getLast());

    try expectEqual(arr.getNextFreeIndex(), 2);
    try expectEqual(arr.getUnusedCount(), size - 2);

    // Validation after third object (stored 2)
    try expect(arr.isIndexUsed(0) == true);
    try expect(arr.isIndexUsed(1) == true);
    try expect(arr.isIndexUsed(2) == false);

    try expect(arr.isLinked(0) == true);
    try expect(arr.isLinked(1) == true);
    try expect(arr.isLinked(2) == false);

    try expect(arr.getElements().len == 2);

    // Fill and check counts
    arr.overwriteAtIndex(size - 1, element1);
    try expectEqual(2, arr.getCount());

    arr.append(element3);
    try expectEqual(3, arr.getCount());
    try expectEqual(arr.getUnusedCount(), size - 3);

    arr.append(element3);
    try expectEqual(4, arr.getCount());
    try expectEqual(arr.getUnusedCount(), size - 4);
    try expect(arr.isFull() == false);
    try expect(arr.isLinked(3) == false);

    arr.set(key3, element3);
    try expectEqual(5, arr.getCount());
    try expectEqual(arr.getUnusedCount(), size - 5);
    try expectEqual(arr.getUnusedCount(), 0);
    try expect(arr.isFull() == true);
    try expect(arr.isLinked(4) == true);

    // FILL AND REMOVE TESTS //
    arr.removeLast();
    try expectEqual(4, arr.getCount());
    try expectEqual(arr.getUnusedCount(), size - 4);
    try expect(arr.isFull() == false);
    try expect(arr.isLinked(4) == false);

    const key4 = 55;
    try expect(arr.isLinked(3) == false);
    arr.link(3, key4);
    try expect(arr.isLinked(3) == true);
    try expect(arr.get(key4) == arr.getAtIndex(3));

    arr.removeAtIndex(3);
    try expectEqual(3, arr.getCount());
    try expectEqual(arr.getUnusedCount(), size - 3);
    try expect(arr.isFull() == false);
    try expect(arr.isLinked(3) == false);

    // remove to swap first and last
    try expect(arr.getFirst() != arr.getAtIndex(2));
    const tempElement = arr.getAtIndex(2);

    try expect(arr.isLinked(0) == true);
    try expect(arr.isKeyUsed(key1) == true);
    arr.removeAtKey(key1);

    try expect(arr.getFirst() == tempElement);
    try expect(arr.isKeyUsed(key1) == false);
    try expect(arr.isLinked(0) == false);
    try expect(arr.isLinked(2) == false);
    try expect(arr.isLinked(1) == true);

    // Swap tests
    try expect(arr.isLinked(0) == false);
    arr.link(0, key4);
    try expect(arr.isLinked(1) == true);
    const e1 = arr.get(key2);
    const e2 = arr.get(key4);
    try expect(e1 != e2);

    try expect(e2 == arr.getAtIndex(0));
    try expect(e1 == arr.getAtIndex(1));

    arr.swap(key2, key4);
    try expect(e1 == arr.getAtIndex(0));
    try expect(e2 == arr.getAtIndex(1));

    arr.swapAtIndex(0, 1);
    try expect(e2 == arr.getAtIndex(0));
    try expect(e1 == arr.getAtIndex(1));

    arr.unlink(key2);
    try expect(arr.isLinked(0) == true);
    try expect(arr.isLinked(1) == false);
    try expect(e2 == arr.getAtIndex(0));
    try expect(e1 == arr.getAtIndex(1));

    arr.swapOnlyElementAtIndex(0, 1);
    try expect(arr.isLinked(0) == true);
    try expect(arr.isLinked(1) == false);
    try expect(e2 == arr.getAtIndex(1));
    try expect(e1 == arr.getAtIndex(0));
}
