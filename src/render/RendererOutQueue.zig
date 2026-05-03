const FixedList = @import("../.structures/FixedList.zig").FixedList;
const Window = @import("../window/Window.zig").Window;
const std = @import("std");

pub const RendererOutQueue = struct {
    rendererOutEvents: FixedList(RendererOutEvent, 127) = .{},

    pub fn append(self: *RendererOutQueue, rendererEvent: RendererOutEvent) void {
        self.rendererOutEvents.append(rendererEvent) catch |err| std.debug.print("RendererOutQueue.appendEvent failed: {}\n", .{err});
    }

    pub fn get(self: *RendererOutQueue) []const RendererOutEvent {
        return self.rendererOutEvents.constSlice();
    }

    pub fn clear(self: *RendererOutQueue) void {
        self.rendererOutEvents.clear();
    }

    pub const RendererOutEvent = union(enum) {
        framePresentedForWindow: Window.WindowId,
    };
};
