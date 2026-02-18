// /// Creates a MapArray Type which links a sparse array of keys and a dense array of any type bidirectionally.
// /// (This is more performant than a hash map and does not have hash collisions at the cost of more memory)
// ///
// /// - For performance/awareness reasons all operations manipulating the MapArray DO NOT CHECK VALIDITY of indices, keys, elements or links!
// ///     (can still be done if wished by using the internally provided "is*" bool and getter functions)
// /// - ALL operations are O(1) the only exception to this is getUsedKeyCount()
// /// - removeAtKey() and removeAtIndex() replace the deleted element with the last element
// /// - Keys are validated using an sentinel value that is reserved for empty keys
// /// - Elements can be added using a key for lookup using the set() function
// /// - Elements added using setAtIndex() or append() will not allow access via key and are not internally linked to a key yet
// ///     (can still be linked later using the link() function)
// /// - The MapArray is fully stack allocated and automatically creates internal types for minimal memory footprint
// ///
// /// @param elementType: type, The type of elements to store
// /// @param size: u32, Maximum number of elements that can be stored
// /// @param keyType: type, The type of sparse keys (must be an unsigned integer type)
// /// @param keyMax: u32, Maximum value a key can have (must be >= size)
// /// @param keyMin: u32, Minimum value a key can have
// ///
// /// example usage:
// /// const MyMapArray = CreateMapArray(Vec4, 1000, u32, 99999, 9999);
// /// var arr = MyMapArray{};
// /// arr.set(100, 42);
// /// arr.append(99);
// ///
// /// *Hint: This can also be used as a general Map storing Indices for multiple Arrays by storing an unsigned integer type as elementType!*
// /// *Hint2: It is strongly adviced to keep size, keyMax and keyMin small, higher values can flood memory very quickly!
// ///  (sizeOf(MapArray) = (keyType keyRange) + (keyType size) + (elements size)*
// ///
// /// implementation details:
// /// - elementLimit: Last elements array Index
// /// - keyLimit: Last keys array index
// /// - usedKeyCount: Number of keys within the valid range of min and max
// /// - smallKeyType: Smallest possible unsigned integer type that can store usedKeyCount + 1 (sentinelValue)
// /// - indexType: Smallest possible unsigned integer type that can store the number of Elements
// ///
// /// - key: Used as keys array index,
// /// - index: Used as index for the links and elements arrays
// ///
// /// - count: Number of elements stored, also describes next available index;
// /// - keys: The sparse Array of index values for the links and elements arrays
// /// - elements: The dense array of elements
// ///
// ///
// const std = @import("std");
// const testing = std.testing;
// const expect = testing.expect;
// const expectEqual = testing.expectEqual;
// const CreateMapArray = @import("MapArray.zig").CreateMapArray;

// test "MapArrayTest" {
//     const elementType = u32;
//     const size = 5;
//     const keyType = u16;
//     const keyMax = 99;
//     const keyMin = 10;

//     const TestMapArray = CreateMapArray(elementType, size, keyType, keyMax, keyMin);
//     var arr = TestMapArray{};

//     // Validations
//     try expect(arr.isKeyUsed(keyMin) == false);
//     try expect(arr.isKeyUsed(keyMax) == false);

//     try expect(arr.isKeyValid(keyMin - 1) == false);
//     try expect(arr.isKeyValid(keyMin) == true);
//     try expect(arr.isKeyValid(keyMax) == true);
//     try expect(arr.isKeyValid(keyMax + 1) == false);

//     try expectEqual(keyMax, arr.getUpperKeyLimit());
//     try expectEqual(keyMin, arr.getLowerKeyLimit());

//     try expectEqual(size - 1, arr.getLastValidIndex());
//     try expectEqual(size, arr.getMaximumElements());

//     try expectEqual(arr.getPossibleKeyCount(), keyMax - keyMin + 1); // because its inclusive
//     try expectEqual(arr.getNextFreeIndex(), 0);
//     try expectEqual(arr.getUnusedCount(), size);

//     try expect(arr.isKeyUsedAndValid(keyMin - 1) == false);
//     try expect(arr.isKeyUsedAndValid(keyMin) == false);
//     try expect(arr.isKeyUsedAndValid(keyMax) == false);
//     try expect(arr.isKeyUsedAndValid(keyMax + 1) == false);

//     try expect(arr.isIndexUsed(0) == false);
//     try expect(arr.isIndexUsed(1) == false);
//     try expect(arr.isIndexUsed(size) == false);

//     try expect(arr.isIndexValid(0) == true);
//     try expect(arr.isIndexValid(size - 1) == true);
//     try expect(arr.isIndexValid(size) == false);
//     try expect(arr.isIndexValid(size + 1) == false);

//     try expect(arr.isLinked(0) == false);
//     try expect(arr.isLinked(size - 1) == false);

//     try expect(arr.isFull() == false);

//     try expect(arr.getElements().len == 0);
//     try expect(arr.getElementsArrayPtr() == &arr.elements);

//     // check if all Keys and Links have reserved Sentinel Value
//     for (arr.links) |link| try expectEqual(link, keyMax - keyMin + 2); // one for sentinel and one for index being inclusive
//     try expectEqual(0, arr.getCount());

//     const element1 = 42;
//     const element2 = 333;
//     const element3 = 1234;
//     const key1 = 84;
//     const key2 = 89;
//     const key3 = 66;

//     // Validations before first object
//     try expect(arr.isKeyUsed(key1) == false);
//     try expect(arr.isKeyUsed(key2) == false);

//     try expect(arr.isKeyValid(key1) == true);
//     try expect(arr.isKeyValid(key2) == true);

//     try expect(arr.isKeyUsedAndValid(key1) == false);
//     try expect(arr.isKeyUsedAndValid(key2) == false);

//     try expect(arr.isLinked(0) == false);
//     try expect(arr.isLinked(1) == false);

//     // set
//     arr.set(key1, element1);
//     try expectEqual(element1, arr.get(key1));
//     try expectEqual(1, arr.getCount());
//     try expect(arr.isKeyUsed(key1) == true);

//     try expect(arr.getElements().len == 1);
//     try expectEqual(arr.getNextFreeIndex(), 1);
//     try expectEqual(arr.getUnusedCount(), size - 1);

//     // Validations after first object
//     try expect(arr.isKeyUsed(key1) == true);
//     try expect(arr.isKeyValid(key1) == true);
//     try expect(arr.isKeyUsedAndValid(key1) == true);

//     try expect(arr.isIndexUsed(0) == true);
//     try expect(arr.isIndexUsed(1) == false);
//     try expect(arr.isIndexUsed(size) == false);

//     try expect(arr.isLinked(0) == true);
//     try expect(arr.isLinked(1) == false);

//     try expect(arr.get(key1) == element1);
//     try expect(arr.getAtIndex(0) == element1);
//     try expect(arr.getFirst() == arr.getAtIndex(0));

//     // set while key is already used
//     arr.set(key1, element2);
//     try expectEqual(1, arr.getCount());
//     try expect(arr.isKeyUsed(key1) == true);

//     try expect(arr.getElements().len == 1);
//     try expectEqual(arr.getNextFreeIndex(), 1);
//     try expectEqual(arr.getUnusedCount(), size - 1);

//     // Validation after second object (stored 1)
//     try expect(arr.isIndexUsed(0) == true);
//     try expect(arr.isIndexUsed(1) == false);

//     try expect(arr.isLinked(0) == true);
//     try expect(arr.isLinked(1) == false);

//     try expect(arr.get(key1) == element2);
//     try expect(arr.getPtr(key1).* == element2);
//     try expect(arr.getAtIndex(0) == element2);
//     try expect(arr.getPtrAtIndex(0).* == arr.getAtIndex(0));
//     try expect(arr.getFirst() == arr.getAtIndex(0));
//     try expect(arr.getFirst() == arr.getLast());
//     try expect(arr.getFirst() == arr.getLast());
//     try expect(arr.getFirstPtr() == arr.getLastPtr());

//     // setMany with 1 new key
//     try expect(arr.isKeyUsed(key2) == false);
//     arr.setMany(&.{ key1, key2 }, &.{ element1, element2 });
//     try expectEqual(2, arr.getCount());
//     try expect(arr.isKeyUsed(key2) == true);

//     try expect(arr.get(key1) == element1);
//     try expect(arr.getPtr(key1).* == element1);
//     try expect(arr.getAtIndex(0) == element1);

//     try expect(arr.get(key2) == element2);
//     try expect(arr.getPtr(key2).* == element2);
//     try expect(arr.getAtIndex(1) == element2);

//     try expect(arr.getFirst() == arr.getAtIndex(0));
//     try expect(arr.getFirst() == arr.getFirstPtr().*);
//     try expect(arr.getFirst() != arr.getAtIndex(1));
//     try expect(arr.getFirst() != arr.getLast());

//     try expectEqual(arr.getNextFreeIndex(), 2);
//     try expectEqual(arr.getUnusedCount(), size - 2);

//     // Validation after third object (stored 2)
//     try expect(arr.isIndexUsed(0) == true);
//     try expect(arr.isIndexUsed(1) == true);
//     try expect(arr.isIndexUsed(2) == false);

//     try expect(arr.isLinked(0) == true);
//     try expect(arr.isLinked(1) == true);
//     try expect(arr.isLinked(2) == false);

//     try expect(arr.getElements().len == 2);

//     // Fill and check counts
//     arr.overwriteAtIndex(size - 1, element1);
//     try expectEqual(2, arr.getCount());

//     arr.append(element3);
//     try expectEqual(3, arr.getCount());
//     try expectEqual(arr.getUnusedCount(), size - 3);

//     arr.append(element3);
//     try expectEqual(4, arr.getCount());
//     try expectEqual(arr.getUnusedCount(), size - 4);
//     try expect(arr.isFull() == false);
//     try expect(arr.isLinked(3) == false);

//     arr.set(key3, element3);
//     try expectEqual(5, arr.getCount());
//     try expectEqual(arr.getUnusedCount(), size - 5);
//     try expectEqual(arr.getUnusedCount(), 0);
//     try expect(arr.isFull() == true);
//     try expect(arr.isLinked(4) == true);

//     // FILL AND REMOVE TESTS //
//     arr.removeLast();
//     try expectEqual(4, arr.getCount());
//     try expectEqual(arr.getUnusedCount(), size - 4);
//     try expect(arr.isFull() == false);
//     try expect(arr.isLinked(4) == false);

//     const key4 = 55;
//     try expect(arr.isLinked(3) == false);
//     arr.link(3, key4);
//     try expect(arr.isLinked(3) == true);
//     try expect(arr.get(key4) == arr.getAtIndex(3));

//     arr.removeAtIndex(3);
//     try expectEqual(3, arr.getCount());
//     try expectEqual(arr.getUnusedCount(), size - 3);
//     try expect(arr.isFull() == false);
//     try expect(arr.isLinked(3) == false);

//     // remove to swap first and last
//     try expect(arr.getFirst() != arr.getAtIndex(2));
//     const tempElement = arr.getAtIndex(2);

//     try expect(arr.isLinked(0) == true);
//     try expect(arr.isKeyUsed(key1) == true);
//     arr.removeAtKey(key1);

//     try expect(arr.getFirst() == tempElement);
//     try expect(arr.isKeyUsed(key1) == false);
//     try expect(arr.isLinked(0) == false);
//     try expect(arr.isLinked(2) == false);
//     try expect(arr.isLinked(1) == true);

//     // Swap tests
//     try expect(arr.isLinked(0) == false);
//     arr.link(0, key4);
//     try expect(arr.isLinked(1) == true);
//     const e1 = arr.get(key2);
//     const e2 = arr.get(key4);
//     try expect(e1 != e2);

//     try expect(e2 == arr.getAtIndex(0));
//     try expect(e1 == arr.getAtIndex(1));

//     arr.swap(key2, key4);
//     try expect(e1 == arr.getAtIndex(0));
//     try expect(e2 == arr.getAtIndex(1));

//     arr.swapAtIndex(0, 1);
//     try expect(e2 == arr.getAtIndex(0));
//     try expect(e1 == arr.getAtIndex(1));

//     arr.unlink(key2);
//     try expect(arr.isLinked(0) == true);
//     try expect(arr.isLinked(1) == false);
//     try expect(e2 == arr.getAtIndex(0));
//     try expect(e1 == arr.getAtIndex(1));

//     arr.swapOnlyElementAtIndex(0, 1);
//     try expect(arr.isLinked(0) == true);
//     try expect(arr.isLinked(1) == false);
//     try expect(e2 == arr.getAtIndex(1));
//     try expect(e1 == arr.getAtIndex(0));
// }
