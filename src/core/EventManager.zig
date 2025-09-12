const std = @import("std");
const AppEvent = config.AppEvent;
const config = @import("../config.zig");
const CreateMapArray = @import("../structures/MapArray.zig").CreateMapArray;

pub const KeyState = enum { pressed, released };
pub const KeyEvent = struct { key: c_uint, event: KeyState };
pub const MouseMovement = struct { xChange: f32, yChange: f32 };

pub const KeyAssignments = struct {
    device: enum { mouse, keyboard },
    state: KeyState,
    cycle: enum { oneTime, repeat },
    appEvent: AppEvent,
    key: c_uint,
};

pub const SDL_KEY_MAX = 512;
pub const SDL_MOUSE_MAX = 24;

pub const EventManager = struct {
    keyStates: CreateMapArray(KeyState, SDL_KEY_MAX + SDL_MOUSE_MAX, c_uint, SDL_KEY_MAX + SDL_MOUSE_MAX, 0) = .{}, // 512 SDL Keys, 24 for Mouse
    appEvents: std.BoundedArray(AppEvent, 127) = .{},
    mouseMoveX: f32 = 0,
    mouseMoveY: f32 = 0,

    pub fn mapKeyEvents(self: *EventManager, keyEvents: []KeyEvent) void {
        for (keyEvents) |keyEvent| {
            if (self.keyStates.isIndexValid(keyEvent.key) == false) {
                std.debug.print("Key {} Invalid\n", .{keyEvent.key});
                continue;
            }
            self.keyStates.set(keyEvent.key, if (keyEvent.event == .pressed) .pressed else .released);

            if (config.KEY_EVENT_INFO == true) std.debug.print("Key {} pressed \n", .{keyEvent.key});
        }
        if (config.KEY_EVENT_INFO == true) std.debug.print("KeyStates {}\n", .{self.keyStates.count});
    }

    pub fn mapMouseMovements(self: *EventManager, movements: []MouseMovement) void {
        for (movements) |movement| {
            self.mouseMoveX += movement.xChange;
            self.mouseMoveY += movement.yChange;

            if (config.MOUSE_MOVEMENT_INFO == true) std.debug.print("Mouse Moved x:{} y:{}\n", .{ movement.xChange, movement.yChange });
        }
        if (config.MOUSE_MOVEMENT_INFO == true)
            std.debug.print("Mouse Total Movement x:{} y:{}, processed {} movements\n", .{ self.mouseMoveX, self.mouseMoveY, movements.len });
    }

    pub fn getAppEvents(self: *EventManager) []AppEvent {
        for (config.keyAssignments) |assignment| {
            const actualKey = switch (assignment.device) {
                .keyboard => assignment.key,
                .mouse => assignment.key + SDL_KEY_MAX,
            };
            // If key is valid check if value at key is same as assignment state
            if (self.keyStates.isKeyUsed(actualKey) == true) {
                const keyState = self.keyStates.get(actualKey);

                if (keyState == assignment.state) {
                    self.appendAppEvent(assignment.appEvent);
                    if (assignment.cycle == .oneTime) self.keyStates.set(actualKey, .released);
                }
            }
        }
        return self.appEvents.slice();
    }

    pub fn appendAppEvent(self: *EventManager, event: AppEvent) void {
        self.appEvents.append(event) catch |err|
            std.debug.print("EventManager.appendEvent failed: {}\n", .{err});
    }

    pub fn clearAppEvents(self: *EventManager) void {
        self.appEvents.clear();
    }

    pub fn resetMouseChange(self: *EventManager) void {
        self.mouseMoveX = 0;
        self.mouseMoveY = 0;
    }
};
