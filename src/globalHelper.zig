const std = @import("std");

pub fn String(comptime capacity: u32, comptime default: []const u8) type {
    return struct {
        const Self = @This();

        comptime {
            if (capacity < default.len) @compileError("String Length too small to fit Default");
        }

        content: [capacity]u8 = init_content: {
            var initial: [capacity]u8 = undefined;
            @memcpy(initial[0..default.len], default[0..default.len]);
            break :init_content initial;
        },
        len: usize = default.len,

        pub fn string(newName: []const u8) !Self {
            if (newName.len > capacity) return error.StringCantFitNewString;

            var self = Self{}; // Starts with default content
            self.len = newName.len;
            @memcpy(self.content[0..newName.len], newName);
            return self;
        }

        pub fn fill(self: *Self, newString: []const u8) void {
            self.len = if (newString.len > capacity) capacity else newString.len;
            @memcpy(self.content[0..self.len], newString[0..self.len]);
        }

        pub fn set(self: *Self, newString: []const u8) !void {
            if (newString.len > capacity) return error.StringCantFitNewString;
            self.len = newString.len;
            @memcpy(self.content[0..self.len], newString[0..self.len]);
        }

        pub fn get(self: *const Self) []const u8 {
            return self.content[0..self.len];
        }
    };
}

pub fn Id(comptime Int: type, comptime tag: anytype) type {
    return enum(Int) {
        _,
        const IdSelf = @This();
        comptime {
            _ = tag;
        }

        pub fn id(integer: Int) IdSelf {
            return @enumFromInt(integer);
        }

        pub fn val(self: IdSelf) Int {
            return @intFromEnum(self);
        }
    };
}

pub fn IdAdvanced(comptime Int: type, comptime tag: anytype, comptime fields: []const struct { @Type(.enum_literal), ?Int }) type {
    return packed struct {
        idEnum: Enum,
        const Self = @This();
        comptime {
            _ = tag;
        }

        pub const Enum = blk: {
            var enumFields: [fields.len]std.builtin.Type.EnumField = undefined;
            for (fields, 0..) |field, index| enumFields[index] = .{ .name = @tagName(field[0]), .value = field[1] orelse std.math.maxInt(Int) - index };
            break :blk @Type(.{ .@"enum" = .{ .tag_type = Int, .fields = &enumFields, .decls = &.{}, .is_exhaustive = false } });
        };

        pub fn id(integer: Int) Self {
            return .{ .idEnum = @enumFromInt(integer) };
        }

        pub fn val(self: Self) Int {
            return @intFromEnum(self.idEnum);
        }

        pub fn get(idEnum: Enum) Self {
            return .{ .idEnum = idEnum };
        }
    };
}
