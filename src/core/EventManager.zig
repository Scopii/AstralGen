const CreateMapArray = @import("../structures/MapArray.zig").CreateMapArray;
const FixedList = @import("../structures/FixedList.zig").FixedList;
const AppEvent = @import("../configs/appConfig.zig").AppEvent;
const ac = @import("../configs/appConfig.zig");
const std = @import("std");

pub const KeyState = enum { pressed, released, blocked };
pub const KeyEvent = struct { key: c_uint, event: KeyState };
pub const MouseMovement = struct { xChange: f32, yChange: f32 };

pub const KeyMapping = struct {
    device: enum { mouse, keyboard },
    state: KeyState,
    cycle: enum { oneTime, repeat, oneBlock },
    appEvent: AppEvent,
    key: c_uint,
};

pub const SDL_KEY_MAX = 512;
pub const SDL_MOUSE_MAX = 24;

pub const EventManager = struct {
    keyStates: CreateMapArray(KeyState, SDL_KEY_MAX + SDL_MOUSE_MAX, c_uint, SDL_KEY_MAX + SDL_MOUSE_MAX, 0) = .{}, // 512 SDL Keys, 24 for Mouse
    appEvents: FixedList(AppEvent, 127) = .{},

    pub fn mapKeyEvents(self: *EventManager, keyEvents: []KeyEvent) void {
        for (keyEvents) |keyEvent| {
            if (self.keyStates.isIndexValid(keyEvent.key) == false) {
                std.debug.print("Key {} Invalid\n", .{keyEvent.key});
                continue;
            }

            if (self.keyStates.isKeyUsed(keyEvent.key)) {
                const keyState = self.keyStates.get(keyEvent.key);
                if (keyState == .blocked and keyEvent.event == .pressed) continue;
            }

            self.keyStates.set(keyEvent.key, if (keyEvent.event == .pressed) .pressed else .released);
            if (ac.KEY_EVENT_INFO == true) std.debug.print("Key {} pressed \n", .{keyEvent.key});
        }
        if (ac.KEY_EVENT_INFO == true) std.debug.print("KeyStates {}\n", .{self.keyStates.count});
    }

    pub fn getAppEvents(self: *EventManager) []AppEvent {
        for (ac.keyMap) |assignment| {
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
                    if (assignment.cycle == .oneBlock) self.keyStates.set(actualKey, .blocked);
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

};
