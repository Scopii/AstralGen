const std = @import("std");
const KeyEvents = @import("../platform/WindowManager.zig").KeyEvent;
const config = @import("../config.zig");
const CreateMapArray = @import("../structures/MapArray.zig").CreateMapArray;

pub const AppEvent = enum {
    camForward,
    camBackward,
    camLeft,
    camRight,
    camUp,
    camDown,

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
                config.CAMERA_FORWARD_KEY.key => self.appEvents.append(.camForward) catch |err| std.debug.print("Could not Append KeyEvent {}", .{err}),
                config.CAMERA_BACKWARD_KEY.key => self.appEvents.append(.camBackward) catch |err| std.debug.print("Could not Append KeyEvent {}", .{err}),
                config.CAMERA_LEFT_KEY.key => self.appEvents.append(.camLeft) catch |err| std.debug.print("Could not Append KeyEvent {}", .{err}),
                config.CAMERA_RIGHT_KEY.key => self.appEvents.append(.camRight) catch |err| std.debug.print("Could not Append KeyEvent {}", .{err}),
                config.CAMERA_UP_KEY.key => self.appEvents.append(.camUp) catch |err| std.debug.print("Could not Append KeyEvent {}", .{err}),
                config.CAMERA_DOWN_KEY.key => self.appEvents.append(.camDown) catch |err| std.debug.print("Could not Append KeyEvent {}", .{err}),

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
