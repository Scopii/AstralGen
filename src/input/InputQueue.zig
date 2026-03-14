const FixedList = @import("../.structures/FixedList.zig").FixedList;
const std = @import("std");
const keyEvent = @import("InputSys.zig").KeyEvent;

pub const InputQueue = struct {
    inputEvents: FixedList(InputEvent, 127) = .{},

    pub fn append(self: *InputQueue, inputEvent: InputEvent) void {
        self.inputEvents.append(inputEvent) catch |err| std.debug.print("InputQueue.appendEvent failed: {}\n", .{err});
    }

    pub fn get(self: *InputQueue) []const InputEvent {
        return self.inputEvents.constSlice();
    }

    pub fn clear(self: *InputQueue) void {
        self.inputEvents.clear();
    }
};

pub const InputEvent = union(enum) {
    keyEvent: keyEvent,
    mouseMove: struct { x: f32, y: f32 },
};
