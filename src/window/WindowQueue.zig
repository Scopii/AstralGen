const TexId = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexId;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const EntityId = @import("../ecs/EntityData.zig").EntityId;
const std = @import("std");

pub const WindowQueue = struct {
    windowEvents: FixedList(WindowEvent, 127) = .{},

    pub fn append(self: *WindowQueue, windowEvent: WindowEvent) void {
        self.windowEvents.append(windowEvent) catch |err| std.debug.print("InputQueue.appendEvent failed: {}\n", .{err});
    }

    pub fn get(self: *WindowQueue) []const WindowEvent {
        return self.windowEvents.constSlice();
    }

    pub fn clear(self: *WindowQueue) void {
        self.windowEvents.clear();
    }
};

pub const WindowEvent = union(enum) {
    addWindow: struct { title: [*c]const u8, w: c_int, h: c_int, renderTexId: TexId, x: c_int, y: c_int, resize: bool, texIds: []const TexId, camEntityId: EntityId },
};
