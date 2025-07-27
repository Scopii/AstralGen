const std = @import("std");

fn FindSmallestIntType(number: usize) type {
    if (number <= 1) return u1;
    if (number <= 3) return u2;
    if (number <= 7) return u3;
    if (number <= 15) return u4;
    if (number <= 31) return u5;
    if (number <= 63) return u6;
    if (number <= 127) return u7;
    if (number <= 255) return u8;
    if (number <= 511) return u9;
    if (number <= 1023) return u10;
    if (number <= 2047) return u11;
    if (number <= 4095) return u12;
    if (number <= 8191) return u13;
    if (number <= 16_383) return u14;
    if (number <= 31_767) return u15;
    if (number <= 65_535) return u16;
    if (number <= 131_071) return u17;
    if (number <= 262_143) return u18;
    if (number <= 524_287) return u19;
    if (number <= 1_048_575) return u20;
    if (number <= 2_097_151) return u21;
    if (number <= 4_194_303) return u22;
    if (number <= 8_388_607) return u23;
    if (number <= 16_777_215) return u24;
    if (number <= 33_554_431) return u25;
    if (number <= 67_108_863) return u26;
    if (number <= 134_217_727) return u27;
    if (number <= 268_435_455) return u28;
    if (number <= 536_870_911) return u29;
    if (number <= 1_073_741_823) return u30;
    if (number <= 2_147_483_647) return u31;
    if (number <= 4_294_967_295) return u32;
}

pub fn CreateMapArray(comptime elementType: type, comptime keyType: type, comptime size: u32) type {
    // Choose smallest int for size
    const IndexType = FindSmallestIntType(size);
    const sentinel = std.math.maxInt(IndexType);
    const keyCount = std.math.maxInt(keyType);

    return struct {
        const Self = @This();
        keys: [keyCount]keyType = .{sentinel} ** keyCount, //Keys store Indices for the Elements and their Links
        elements: [size]elementType = undefined, //Elements store the actual data
        links: [size]keyType = undefined, //Links connect the Elements with their Keys
        count: IndexType = 0, //Count stores current usage
        size: IndexType = size,

        pub fn addWithKey(self: *Self, key: keyType, element: elementType) !void {
            if (self.isFull() == true) return error.addWithKey;

            if (key == sentinel) {
                std.debug.print("MapArray: Key {} reserved for being empty\n", .{sentinel});
                return error.addWithKey;
            }

            if (key >= keyCount) {
                std.debug.print("MapArray: Key Out of Bounds ({}-{})\n", .{ 0, keyCount - 1 });
                return error.addWithKey;
            }

            const count = self.count;
            self.elements[count] = element;
            self.keys[key] = count;
            self.links[count] = key;
            self.count += 1;
        }

        pub fn removeAtIndex(self: *Self, index: IndexType) !void {
            if (self.isIndexValid(index) == false) return error.removeAtIndex;
            const lastIndex = self.count - 1;

            self.keys[self.links[index]] = sentinel;

            if (index < lastIndex) {
                const lastLink = self.links[lastIndex];
                self.elements[index] = self.elements[lastIndex];
                self.links[index] = lastLink;
                self.keys[lastLink] = index;
            }
            self.count -= 1;
        }

        pub fn fetchRemoveAtIndex(self: *Self, index: IndexType) !elementType {
            if (self.isIndexValid(index) == false) return error.fetchRemoveAtIndex;
            const removedElement = self.elements[index];
            const lastIndex = self.count - 1;

            self.keys[self.links[index]] = sentinel;

            if (index < lastIndex) {
                const lastLink = self.links[lastIndex];
                self.elements[index] = self.elements[lastIndex];
                self.links[index] = lastLink;
                self.keys[lastLink] = index;
            }
            self.count -= 1;
            return removedElement;
        }

        pub fn getCount(self: *const Self) IndexType {
            return self.count;
        }

        pub fn isEmpty(self: *const Self) bool {
            if (self.count <= 0) {
                std.debug.print("MapArray: No Elements stored\n", .{});
                return true;
            }
            return false;
        }

        pub fn getFromKey(self: *Self, key: keyType) !elementType {
            if (self.isKeyValid(key) == false) return error.getFromKey;
            return self.elements[self.keys[key]];
        }

        pub fn getLinkFromKey(self: *const Self, key: keyType) !keyType {
            if (self.isKeyValid(key) == false) return error.getLinkFromKey;
            return self.links[self.keys[key]];
        }

        pub fn getLinkAtIndex(self: *const Self, index: IndexType) !keyType {
            if (self.isIndexValid(index) == false) return error.getLinkAtIndex;
            return self.links[index];
        }

        pub fn getLast(self: *const Self) !elementType {
            if (self.isEmpty() == true) return error.getLast;
            return self.elements[self.count - 1];
        }

        pub fn getLastLink(self: *const Self) !keyType {
            if (self.isEmpty() == true) return error.getLastLink;
            return self.links[self.count - 1];
        }

        pub fn getLastPtr(self: *Self) !*elementType {
            if (self.isEmpty()) return error.getLast;
            return &self.elements[self.count - 1];
        }

        pub fn getPtrFromKey(self: *Self, key: keyType) !*elementType {
            if (self.isKeyValid(key) == false) return error.getFromKey;
            return &self.elements[self.keys[key]];
        }

        pub fn getAtIndex(self: *const Self, index: IndexType) !elementType {
            if (self.isIndexValid(index) == false) return error.getAtIndex;
            return self.elements[index];
        }

        pub fn getPtrAtIndex(self: *Self, index: IndexType) !*elementType {
            if (self.isIndexValid(index) == false) return error.getAtIndex;
            return &self.elements[index];
        }

        pub fn removeLast(self: *Self) !void {
            if (self.isEmpty() == true) return error.removeLast;
            self.count -= 1;
        }

        pub fn getIndexFromKey(self: *Self, key: keyType) !IndexType {
            if (self.isKeyValid(key) == false) return error.getIndexFromKey;
            return self.keys[key];
        }

        pub fn isFull(self: *Self) bool {
            if (self.count >= self.size) {
                std.debug.print("MapArray: Cant add more than {} Elements\n", .{self.count});
                return true;
            }
            return false;
        }

        pub fn isIndexValid(self: *const Self, index: IndexType) bool {
            if (self.isEmpty() == true) return false;
            if (index >= self.count) {
                std.debug.print("MapArray: Index Access too big {} from {}\n", .{ index, self.count });
                return false;
            }
            if (index > self.size - 1 or index < 0) {
                std.debug.print("MapArray: Index Access Out of Bounds ({}-{})\n", .{ 0, self.size - 1 });
                return false;
            }
            return true;
        }

        pub fn isKeyValid(self: *Self, key: keyType) bool {
            if (self.isEmpty() == true) return false;
            if (key == sentinel) {
                std.debug.print("MapArray: Key {} reserved for being empty\n", .{sentinel});
                return false;
            }
            if (key >= keyCount) {
                std.debug.print("MapArray: Key Out of Bounds ({}-{})\n", .{ 0, keyCount - 1 });
                return false;
            }
            if (self.keys[key] == sentinel) {
                std.debug.print("No Element stored for Key {}\n", .{key});
                return false;
            }
            return true;
        }

        pub fn removeFromKey(self: *Self, key: keyType) !void {
            if (self.isKeyValid(key) == false) return error.removeFromKey;
            const index = self.keys[key];
            self.keys[self.links[index]] = sentinel;
            self.keys[key] = index;
            self.elements[index] = try self.getLast();
            self.links[index] = try self.getLastLink();

            self.count -= 1;
        }

        pub fn fetchRemoveFromKey(self: *Self, key: keyType) !elementType {
            if (self.isKeyValid(key) == false) return error.fetchRemoveFromKey;
            const element = try self.getFromKey(key);
            try self.removeFromKey(key);
            return element;
        }

        pub fn printAll(self: *Self) void {
            std.debug.print("\n", .{});
            for (0..self.count) |i| {
                std.debug.print("Element {} has key {} which points to Index {}\n", .{ self.elements[i], self.links[i], self.keys[self.links[i]] });
            }
            std.debug.print("\n", .{});
        }

        pub fn getLastKey(_: *Self) keyType {
            return keyCount - 1;
        }

        pub fn getSentinel(_: *Self) keyType {
            return sentinel;
        }
    };
}

// Prototype
pub const MapArray = struct {
    max: u8 = 24,
    keys: [24]u32 = undefined,
    elements: [24]u128 = undefined,
    links: [24]u32 = undefined,
    count: u8 = 0,

    pub fn add(self: *MapArray, key: u32, element: u128) void {
        if (self.count >= self.max - 1) return;

        self.elements[self.count] = element;
        self.links[self.count] = key;
        self.keys[key] = self.count;
        self.count += 1;
    }

    pub fn getCount(self: *MapArray) u8 {
        return self.count;
    }

    pub fn getElement(self: *MapArray, key: u32) u128 {
        return self.elements[self.keys[key]];
    }

    pub fn getPtr(self: *MapArray, key: u32) *u128 {
        return &self.elements[self.keys[key]];
    }

    pub fn getLastElement(self: *MapArray) u128 {
        return self.elements[self.count - 1];
    }

    pub fn getLastPtr(self: *MapArray) *u128 {
        return &self.elements[self.count - 1];
    }

    pub fn getLink(self: *MapArray, key: u32) u32 {
        return self.links[self.keys[key]];
    }

    pub fn getLastLink(self: *MapArray) u32 {
        return self.links[self.count - 1];
    }

    pub fn remove(self: *MapArray, key: u32) void {
        if (self.count <= 0) return;
        const lastElement = self.getLastElement();
        const lastLink = self.getLastLink();

        self.getPtr(key).* = lastElement;
        self.links[key] = lastLink;
        self.keys[lastLink] = key;
        self.count -= 1;
    }

    pub fn removeLast(self: *MapArray) void {
        if (self.count > 0) self.count -= 1 else return;
    }
};
