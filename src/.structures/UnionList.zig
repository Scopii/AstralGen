const FixedList = @import("../.structures/FixedList.zig").FixedList;
const std = @import("std");

pub fn UnionList(comptime EventUnion: type, comptime count: u32) type {
    return struct {
        data: FixedList(u8, @sizeOf(EventUnion) * count) = .{},
        tags: FixedList(std.meta.Tag(EventUnion), count) = .{},
        starts: FixedList(u32, count) = .{}, // Start Byte of every Event

        pub fn append(self: *@This(), event: EventUnion) !void {
            try self.starts.append(self.data.len);

            switch (event) {
                inline else => |*value, tag| {
                    // const size = @sizeOf(@FieldType(EventUnion, @tagName(tag)));
                    // const bytes = std.mem.asBytes(value)[0..size];

                    const bytes = std.mem.asBytes(value);
                    try self.data.appendSlice(bytes);
                    try self.tags.append(tag);
                },
            }
        }

        pub fn length(self: *const @This()) u32 {
            return self.tags.len;
        }

        pub fn get(self: *const @This(), index: u32) EventUnion {
            const startByte = self.starts.constSlice()[index];
            switch (self.tags.constSlice()[index]) {
                inline else => |tag| {
                    const PayloadType = @FieldType(EventUnion, @tagName(tag));
                    const payload: PayloadType = std.mem.bytesToValue(PayloadType, self.data.constSlice()[startByte..][0..@sizeOf(PayloadType)]);
                    return @unionInit(EventUnion, @tagName(tag), payload);
                },
            }
        }

        pub fn clear(self: *@This()) void {
            self.data.clear();
            self.tags.clear();
            self.starts.clear();
        }
    };
}
