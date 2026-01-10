const std = @import("std");

fn FindSmallestIntType(number: usize) type {
    return std.math.IntFittingRange(0, number);
}

pub fn CreateStableMapArray(comptime elementType: type, comptime size: u32, comptime keyType: type, comptime keyMax: u32, comptime keyMin: u32) type {
    const usedKeyCount = keyMax - keyMin + 1;
    const sentinel = std.math.maxInt(u32); 

    return struct {
        const Self = @This();
        
        elements: [size]elementType = undefined,
        keys: [usedKeyCount]u32 = .{sentinel} ** usedKeyCount, // MAPPING (Key -> Index)
        freeIndices: [size]u32 = undefined, // INTERNAL FREE LIST
        freeHead: u32 = 0,
        count: u32 = 0,

        pub fn init() Self {
            var self = Self{};
            var i: usize = 0;
            // Fill free stack [size-1, ... 1, 0]
            while (i < size) : (i += 1) {
                self.freeIndices[i] = @intCast(size - 1 - i);
            }
            self.freeHead = size;
            return self;
        }

        pub fn insert(self: *Self, key: keyType, element: elementType) !u32 {
            if (self.freeHead == 0) return error.OutOfMemory;

            self.freeHead -= 1;
            const index = self.freeIndices[self.freeHead];

            const castedKey: usize = @intCast(key - keyMin);
            self.keys[castedKey] = index;
            self.elements[index] = element;
            self.count += 1;

            return index;
        }

        pub fn remove(self: *Self, key: keyType) void {
            const castedKey: usize = @intCast(key - keyMin);
            const index = self.keys[castedKey];
            
            if (index == sentinel) return;

            self.keys[castedKey] = sentinel;
            self.freeIndices[self.freeHead] = index;
            self.freeHead += 1;
            self.count -= 1;
        }

        pub fn get(self: *const Self, key: keyType) elementType {
            const index = self.keys[@intCast(key - keyMin)];
            return self.elements[index];
        }

        pub fn getIndex(self: *const Self, key: keyType) u32 {
            return self.keys[@intCast(key - keyMin)];
        }

        pub fn getPtr(self: *Self, key: keyType) *elementType {
            const index = self.keys[@intCast(key - keyMin)];
            return &self.elements[index];
        }
        
        pub fn isKeyUsed(self: *const Self, key: keyType) bool {
            // Safety check for bounds
            if (key < keyMin or key > keyMax) return false;
            return self.keys[@intCast(key - keyMin)] != sentinel;
        }
        
        pub fn getCount(self: *const Self) u32 {
            return self.count;
        }

        pub const Iterator = struct {
            map: *Self,
            currentKeyIdx: usize = 0,

            pub fn next(self: *Iterator) ?keyType {
                while (self.currentKeyIdx < usedKeyCount) {
                    if (self.map.keys[self.currentKeyIdx] != sentinel) {
                        const k = @as(keyType, @intCast(self.currentKeyIdx)) + keyMin;
                        self.currentKeyIdx += 1;
                        return k;
                    }
                    self.currentKeyIdx += 1;
                }
                return null;
            }
        };

        pub fn iterator(self: *Self) Iterator {
            return .{ .map = self };
        }
    };
}