const KeyPool = @import("KeyPool.zig").KeyPool;
const std = @import("std");
const meta = std.meta;

fn FindSmallestIntType(number: usize) type {
    return std.math.IntFittingRange(0, number);
}

pub fn SOAMap(comptime T: type, comptime cap: usize) type {
    if (@typeInfo(T) != .@"struct") @compileError("SOAMap only supports structs");
    const fields = meta.fields(T);
    const smallKeyType = FindSmallestIntType(cap + 1);
    const sentinel: smallKeyType = @intCast(cap + 1);

    const Arrays = blk: {
        var newFields: [fields.len]std.builtin.Type.StructField = undefined;
        for (fields, &newFields) |f, *nf| {
            const Arr = [cap]f.type;
            nf.* = .{
                .name = f.name,
                .type = Arr,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf(Arr),
            };
        }
        break :blk @Type(.{ .@"struct" = .{
            .layout = .auto,
            .fields = &newFields,
            .decls = &.{},
            .is_tuple = false,
        } });
    };

    return struct {
        const Self = @This();
        pub const Field = meta.FieldEnum(T);

        arrays: Arrays = undefined,
        sparse: [cap]smallKeyType = .{sentinel} ** cap, // key → dense index
        links: [cap]smallKeyType = undefined, // dense index → key (reverse)
        keyPool: KeyPool(smallKeyType, cap) = .{},
        len: usize = 0,

        pub fn insert(self: *Self, item: T) smallKeyType {
            std.debug.assert(self.len < cap);
            const key = self.keyPool.reserveKey();
            const index = self.len;
            self.len += 1;

            self.sparse[key] = @intCast(index);
            self.links[index] = key;
            inline for (fields) |f|
                @field(self.arrays, f.name)[index] = @field(item, f.name);

            return key;
        }

        pub fn swapRemove(self: *Self, key: smallKeyType) void {
            const index: smallKeyType = self.sparse[key];
            const last = self.len - 1;

            self.sparse[key] = sentinel;
            self.keyPool.freeKey(key);

            if (index != last) {
                const lastKey = self.links[last];
                inline for (fields) |f| // move last item into removed slot
                    @field(self.arrays, f.name)[index] = @field(self.arrays, f.name)[last];
                self.links[index] = lastKey;
                self.sparse[lastKey] = index; // fix moved item's sparse entry
            }
            self.len -= 1;
        }

        // Per-field slice — the main advantage over AOS SlotMap
        pub fn slice(self: *Self, comptime field: Field) []meta.FieldType(T, field) {
            return @field(self.arrays, @tagName(field))[0..self.len];
        }

        pub fn getByKey(self: *const Self, key: smallKeyType, comptime field: Field) meta.FieldType(T, field) {
            return @field(self.arrays, @tagName(field))[self.sparse[key]];
        }

        pub fn getPtrByKey(self: *Self, key: smallKeyType, comptime field: Field) *meta.FieldType(T, field) {
            return &@field(self.arrays, @tagName(field))[self.sparse[key]];
        }

        pub fn getByIndex(self: *const Self, index: u32, comptime field: Field) meta.FieldType(T, field) {
            return @field(self.arrays, @tagName(field))[index];
        }

        pub fn getPtrByIndex(self: *Self, index: u32, comptime field: Field) *meta.FieldType(T, field) {
            return &@field(self.arrays, @tagName(field))[index];
        }
    };
}
