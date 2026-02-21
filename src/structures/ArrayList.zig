const std = @import("std");
const meta = std.meta;

pub fn ArrayList(comptime T: type, comptime cap: usize) type {
    if (@typeInfo(T) != .@"struct") @compileError("ArrayList only supports structs");
    const fields = meta.fields(T);

    // Build a parallel struct where each field becomes [cap]FieldType
    const Arrays = blk: {
        var newFields: [fields.len]std.builtin.Type.StructField = undefined;
        for (fields, &newFields) |f, *nf| {
            const Arr = [cap]f.type;
            nf.* = .{
                .name       = f.name,
                .type       = Arr,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment  = @alignOf(Arr),
            };
        }
        break :blk @Type(.{ .@"struct" = .{
            .layout  = .auto,
            .fields  = &newFields,
            .decls   = &.{},
            .is_tuple = false,
        }});
    };

    return struct {
        arrays: Arrays = undefined,
        len: usize = 0,

        const Self = @This();
        pub const capacity = cap;
        pub const Field = meta.FieldEnum(T);

        fn FieldType(comptime field: Field) type {
            return @FieldType(T, @tagName(field));
        }

        pub fn items(self: *Self, comptime field: Field) []FieldType(field) {
            return @field(self.arrays, @tagName(field))[0..self.len];
        }

        pub fn constItems(self: *const Self, comptime field: Field) []const FieldType(field) {
            return @field(self.arrays, @tagName(field))[0..self.len];
        }

        pub fn appendSave(self: *Self, elem: T) error{OutOfMemory}!void {
            if (self.len >= cap) return error.OutOfMemory;
            self.appendUnsave(elem);
        }

        pub fn appendUnsave(self: *Self, elem: T) void {
            std.debug.assert(self.len < cap);
            const i = self.len;
            self.len += 1;
            inline for (fields) |field| {
                @field(self.arrays, field.name)[i] = @field(elem, field.name);
            }
        }

        pub fn get(self: *const Self, index: usize) T {
            std.debug.assert(index < self.len);
            var result: T = undefined;
            inline for (fields) |field| {
                @field(result, field.name) = @field(self.arrays, field.name)[index];
            }
            return result;
        }

        pub fn set(self: *Self, index: usize, elem: T) void {
            std.debug.assert(index < self.len);
            inline for (fields) |field| {
                @field(self.arrays, field.name)[index] = @field(elem, field.name);
            }
        }

        pub fn swapRemove(self: *Self, index: usize) void {
            std.debug.assert(index < self.len);
            const last = self.len - 1;
            if (index != last) {
                inline for (fields) |field| {
                    @field(self.arrays, field.name)[index] = @field(self.arrays, field.name)[last];
                }
            }
            self.len -= 1;
        }

        pub fn pop(self: *Self) ?T {
            if (self.len == 0) return null;
            self.len -= 1;
            return self.get(self.len);
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.len = 0;
        }
    };
}