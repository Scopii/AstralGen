const std = @import("std");
const KeyEvent = @import("../platform/WindowManager.zig").KeyEvent;
const MouseMovement = @import("../platform/WindowManager.zig").MouseMovement;
const config = @import("../config.zig");
const CreateMapArray = @import("../structures/MapArray.zig").CreateMapArray;

pub const AppEvent = enum {
    camForward,
    camBackward,
    camLeft,
    camRight,
    camUp,
    camDown,
    camFovIncrease,
    camFovDecrease,

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
    mouseButtonStates: CreateMapArray(KeyState, 24, c_uint, 24, 0) = .{},
    mouseMovementX: f32 = 0,
    mouseMovementY: f32 = 0,

    pub fn mapKeyEvents(self: *EventManager, keyEvents: []KeyEvent) void {
        for (keyEvents) |keyEvent| {
            self.keyStates.set(keyEvent.key, if (keyEvent.event == .pressed) .pressed else .released);
        }
        //std.debug.print("KeyStates {}\n", .{self.keyStates.count});
    }

    pub fn mapMouseButtonEvents(self: *EventManager, mouseButtonEvents: []KeyEvent) void {
        for (mouseButtonEvents) |mouseButtonEvent| {
            self.mouseButtonStates.set(mouseButtonEvent.key, if (mouseButtonEvent.event == .pressed) .pressed else .released);
        }
        //std.debug.print("MouseStates {}\n", .{self.mouseButtonStates.count});
    }

    pub fn mapMouseMovements(self: *EventManager, movements: []MouseMovement) void {
        for (movements) |movement| {
            self.mouseMovementX += movement.xChange;
            self.mouseMovementY += movement.yChange;
            //std.debug.print("Mouse Moved x:{} y:{}\n", .{ movement.xChange, movement.yChange });
        }
        //std.debug.print("Mouse Total Movement x:{} y:{}, processed {} movements\n", .{ self.mouseMovementX, self.mouseMovementY, movements.len });
    }

    pub fn getAppEvents(self: *EventManager) []AppEvent {
        for (0..self.keyStates.getCount()) |i| {
            const state = self.keyStates.getPtrAtIndex(@intCast(i)).*;
            const link = self.keyStates.links[i];

            switch (link) {
                // State Events
                config.CAM_FORWARD_KEY.key => if (state == config.CAM_FORWARD_KEY.event) self.appendEvent(.camForward),
                config.CAM_BACKWARD_KEY.key => if (state == config.CAM_BACKWARD_KEY.event) self.appendEvent(.camBackward),
                config.CAM_LEFT_KEY.key => if (state == config.CAM_LEFT_KEY.event) self.appendEvent(.camLeft),
                config.CAM_RIGHT_KEY.key => if (state == config.CAM_RIGHT_KEY.event) self.appendEvent(.camRight),
                config.CAM_UP_KEY.key => if (state == config.CAM_UP_KEY.event) self.appendEvent(.camUp),
                config.CAM_DOWN_KEY.key => if (state == config.CAM_DOWN_KEY.event) self.appendEvent(.camDown),
                config.CAM_FOV_INC_KEY.key => if (state == config.CAM_FOV_INC_KEY.event) self.appendEvent(.camFovIncrease),
                config.CAM_FOV_DEC_KEY.key => if (state == config.CAM_FOV_DEC_KEY.event) self.appendEvent(.camFovDecrease),

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
                    std.debug.print("Key {} State {s} not mapped\n", .{ link, @tagName(state) });
                    self.keyStates.removeAtIndex(@intCast(i));
                },
            }
        }

        // Mouse Related
        for (0..self.mouseButtonStates.getCount()) |i| {
            const state = self.mouseButtonStates.getPtrAtIndex(@intCast(i)).*;
            const link = self.mouseButtonStates.links[i];

            switch (link) {
                // State Events
                //config.CAMERA_FORWARD_KEY.key => if (state == config.CAMERA_FORWARD_KEY.event) self.appendEvent(.camForward),

                // One Time Events
                else => {
                    std.debug.print("Mouse Button {} State {s} not mapped\n", .{ link, @tagName(state) });
                    self.mouseButtonStates.removeAtIndex(@intCast(i));
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

    pub fn resetMouseMovement(self: *EventManager) void {
        self.mouseMovementX = 0;
        self.mouseMovementY = 0;
    }
};
