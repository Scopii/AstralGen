const std = @import("std");

/// Creates a MapArray Type which links a sparse array of keys and a dense array of any type bidirectionally.
///
/// - For performance/awareness reasons all operations manipulating the MapArray DO NOT CHECK VALIDITY of indices, keys, elements or links!
///     (can still be done if wished by using the internally provided "is*" bool and getter functions)
/// - ALL operations are O(1)
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
/// implementation deatails:
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
    const keyLimit = keyMax - 1;

    const usedKeyCount = keyMax - keyMin;
    const sentinelValue = usedKeyCount + 1;
    const smallKeyType = FindSmallestIntType(sentinelValue);
    const BitSet = std.bit_set.ArrayBitSet(usize, usedKeyCount);
    const indexType = FindSmallestIntType(size);

    return struct {
        const Self = @This();
        count: indexType = 0,

        bits: BitSet = BitSet.initEmpty(),
        keys: [usedKeyCount]smallKeyType = undefined,

        links: [size]smallKeyType = .{sentinelValue} ** size,
        elements: [size]elementType = undefined,

        pub fn set(self: *Self, key: keyType, element: elementType) void {
            const castedKey: smallKeyType = @intCast(key - keyMin);

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

        pub fn link(self: *Self, index: u32, key: keyType) void {
            const castedKey: smallKeyType = @intCast(key - keyMin);
            self.bits.setValue(castedKey, true);
            self.keys[castedKey] = @intCast(index);
            self.links[index] = castedKey;
        }

        pub fn removeLast(self: *Self) void {
            const key = self.links[self.count - 1];
            if (key != sentinelValue) self.bits.setValue(key, false);
            self.count -= 1;
        }

        pub fn removeAtKey(self: *Self, key: keyType) void {
            self.removeAtIndex(self.keys[key - keyMin]);
        }

        pub fn removeAtIndex(self: *Self, index: u32) void {
            const keyIndex = self.links[index];
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
            self.swapOnlyElementAtIndex(self.keys[key1 - keyMin], self.keys[key2 - keyMin]);
        }

        pub fn swapOnlyElementAtIndex(self: *Self, index1: u32, index2: u32) void {
            const tempElement = self.elements[index1];
            self.elements[index1] = self.elements[index2];
            self.elements[index2] = tempElement;
        }

        pub fn swap(self: *Self, key1: keyType, key2: keyType) void {
            self.swapAtIndex(self.keys[key1 - keyMin], self.keys[key2 - keyMin]);
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
            const castedKey: smallKeyType = @intCast(key - keyMin);
            return self.bits.isSet(castedKey);
        }

        pub fn isKeyUsedAndValid(self: *Self, key: keyType) bool {
            if (self.isKeyValid(key) == false) return false;
            const castedKey: smallKeyType = @intCast(key - keyMin);
            return self.bits.isSet(castedKey);
        }

        pub inline fn isKeyValid(_: *Self, key: keyType) bool {
            return key >= keyMin and (key - keyMin) < usedKeyCount;
        }

        pub inline fn isIndexUsed(self: *Self, index: u32) bool {
            return index < self.count;
        }

        pub inline fn isFull(self: *Self) bool {
            return self.count >= size;
        }

        pub inline fn isIndexValid(_: *Self, index: u32) bool {
            return index <= elementLimit;
        }

        pub inline fn isLinked(self: *Self, index: u32) bool {
            return self.links[index] != sentinelValue;
        }

        pub inline fn getKeyLimit(_: *Self) u32 {
            return keyLimit;
        }

        pub inline fn getLastValidIndex(_: *Self) u32 {
            return elementLimit;
        }

        pub inline fn getMaximumElements(_: *Self) u32 {
            return size;
        }

        pub inline fn getInternalKeyRange(_: *Self) u32 {
            return usedKeyCount;
        }

        pub inline fn getKeyOffset(_: *Self) u32 {
            return keyMin;
        }

        pub inline fn getUsedKeyCount(self: *Self) u32 {
            return @intCast(self.bits.count());
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
    };
}

fn FindSmallestIntType(number: usize) type {
    return std.math.IntFittingRange(0, number - 1);
}
