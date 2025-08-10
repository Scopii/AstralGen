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

pub const KeyState = enum {
    pressed,
    released,
};

pub const EventManager = struct {
    appEvents: std.BoundedArray(AppEvent, 127) = .{},
    keyStates: CreateMapArray(KeyState, 500, c_uint, 500, 0) = .{},

    pub fn mapKeyEvents(self: *EventManager, keyEvents: []KeyEvents) void {
        for (keyEvents) |keyEvent| {
            self.keyStates.set(keyEvent.key, if (keyEvent.event == .pressed) .pressed else .released);
        }
        //std.debug.print("KeyStates {}\n", .{self.keyStates.count});
    }

    pub fn getAppEvents(self: *EventManager) []AppEvent {
        for (0..self.keyStates.getCount()) |i| {
            const state = self.keyStates.getPtrAtIndex(@intCast(i)).*;
            const link = self.keyStates.links[i];

            switch (link) {
                // State Events
                config.CAMERA_FORWARD_KEY.key => if (state == config.CAMERA_FORWARD_KEY.event) self.appendEvent(.camForward),
                config.CAMERA_BACKWARD_KEY.key => if (state == config.CAMERA_BACKWARD_KEY.event) self.appendEvent(.camBackward),
                config.CAMERA_LEFT_KEY.key => if (state == config.CAMERA_LEFT_KEY.event) self.appendEvent(.camLeft),
                config.CAMERA_RIGHT_KEY.key => if (state == config.CAMERA_RIGHT_KEY.event) self.appendEvent(.camRight),
                config.CAMERA_UP_KEY.key => if (state == config.CAMERA_UP_KEY.event) self.appendEvent(.camUp),
                config.CAMERA_DOWN_KEY.key => if (state == config.CAMERA_DOWN_KEY.event) self.appendEvent(.camDown),

                // One Time Events
                config.RESTART_KEY.key => {
                    self.appendEvent(.restartApp);
                    self.keyStates.removeAtIndex(@intCast(i));
                },
                config.CLOSE_KEY.key => {
                    self.appendEvent(.closeApp);
                    self.keyStates.removeAtIndex(@intCast(i));
                },
                else => {
                    std.debug.print("Key {} not mapped\n", .{link});
                    self.keyStates.removeAtIndex(@intCast(i));
                },
            }
        }
        return self.appEvents.slice();
    }

    pub fn appendEvent(self: *EventManager, ev: AppEvent) void {
        self.appEvents.append(ev) catch |err|
            std.debug.print("EventManager.appendEvent failed: {}\n", .{err});
    }

    pub fn cleanupAppEvents(self: *EventManager) void {
        self.appEvents.clear();
    }
};
