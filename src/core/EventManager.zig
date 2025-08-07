const std = @import("std");
const KeyEvents = @import("../platform/WindowManager.zig").KeyEvent;
const config = @import("../config.zig");
const CreateMapArray = @import("../structures/MapArray.zig").CreateMapArray;

pub const AppEvent = enum {
    updateCam,
    closeApp,
    restartApp,
};

const KeyState = enum {
    pressed,
    held,
    released,
    unused,
};

pub const EventManager = struct {
    appEvents: std.BoundedArray(AppEvent, 127) = .{},
    //keyStates: std.BoundedArray(KeyState, 127) = .{},
    //keyStates: CreateMapArray(KeyState, 500, c_uint, 500, 0) = .{},

    pub fn mapKeyEvents(self: *EventManager, keyEvents: []KeyEvents) void {
        for (keyEvents) |keyEvent| {
            switch (keyEvent.key) {
                config.UPDATE_CAM_KEY.key => self.appEvents.append(.updateCam) catch |err| std.debug.print("Could not Append KeyEvent {}", .{err}),
                config.RESTART_KEY.key => self.appEvents.append(.restartApp) catch |err| std.debug.print("Could not Append KeyEvent {}", .{err}),
                config.CLOSE_KEY.key => self.appEvents.append(.closeApp) catch |err| std.debug.print("Could not Append KeyEvent {}", .{err}),
                else => std.debug.print("KeyEvent {} {s} not mapped", .{ keyEvent.key, @tagName(keyEvent.event) }),
            }
        }
    }

    pub fn getAppEvents(self: *EventManager) []AppEvent {
        return self.appEvents.slice();
    }

    pub fn cleanupAppEvents(self: *EventManager) void {
        self.appEvents.clear();
    }
};
