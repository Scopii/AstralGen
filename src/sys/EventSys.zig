const FixedList = @import("../structures/FixedList.zig").FixedList;
const LinkedMap = @import("../structures/LinkedMap.zig").LinkedMap;
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

pub const EventState = @import("../state/EventState.zig").EventState;
pub const InputState = @import("../state/InputState.zig").InputState;

pub const EventSys = struct {
    pub fn mapKeyEvents(eventState: *EventState, inputState: *InputState) void {
        for (inputState.inputEvents.slice()) |keyEvent| {
            if (eventState.keyStates.isIndexValid(keyEvent.key) == false) {
                std.debug.print("Key {} Invalid\n", .{keyEvent.key});
                continue;
            }

            if (eventState.keyStates.isKeyUsed(keyEvent.key)) {
                const keyState = eventState.keyStates.getByKey(keyEvent.key);
                if (keyState == .blocked and keyEvent.event == .pressed) continue;
            }

            eventState.keyStates.upsert(keyEvent.key, if (keyEvent.event == .pressed) .pressed else .released);
            if (ac.KEY_EVENT_INFO == true) std.debug.print("Key {} pressed \n", .{keyEvent.key});
        }
        if (ac.KEY_EVENT_INFO == true) std.debug.print("KeyStates {}\n", .{eventState.keyStates.len});
    }

    pub fn getAppEvents(eventState: *EventState) []AppEvent {
        for (ac.keyMap) |assignment| {
            const actualKey = switch (assignment.device) {
                .keyboard => assignment.key,
                .mouse => assignment.key + SDL_KEY_MAX,
            };
            // If key is valid check if value at key is same as assignment state
            if (eventState.keyStates.isKeyUsed(actualKey) == true) {
                const keyState = eventState.keyStates.getByKey(actualKey);

                if (keyState == assignment.state) {
                    appendAppEvent(eventState, assignment.appEvent);
                    if (assignment.cycle == .oneTime) eventState.keyStates.upsert(actualKey, .released);
                    if (assignment.cycle == .oneBlock) eventState.keyStates.upsert(actualKey, .blocked);
                }
            }
        }
        return eventState.appEvents.slice();
    }

    pub fn appendAppEvent(eventState: *EventState, event: AppEvent) void {
        eventState.appEvents.append(event) catch |err| std.debug.print("EventManager.appendEvent failed: {}\n", .{err});
    }

    pub fn clearAppEvents(eventState: *EventState) void {
        eventState.appEvents.clear();
    }
};
