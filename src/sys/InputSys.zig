pub const EngineQueue = @import("../state/EngineQueue.zig").EngineQueue;
const FixedList = @import("../structures/FixedList.zig").FixedList;
const LinkedMap = @import("../structures/LinkedMap.zig").LinkedMap;
const InputState = @import("../state/InputState.zig").InputState;
const AppEvent = @import("../configs/appConfig.zig").AppEvent;
const ac = @import("../configs/appConfig.zig");
const sdl = @import("../modules/sdl.zig").c;
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

pub const InputSys = struct {
    pub fn getKeyEvents(inputState: *InputState) []KeyEvent {
        return inputState.inputEvents.slice();
    }

    pub fn updateKeyStates(inputState: *InputState) void {
        for (inputState.inputEvents.slice()) |keyEvent| {
            if (inputState.keyStates.isIndexValid(keyEvent.key) == false) {
                std.debug.print("Key {} Invalid\n", .{keyEvent.key});
                continue;
            }

            if (inputState.keyStates.isKeyUsed(keyEvent.key)) {
                const keyState = inputState.keyStates.getByKey(keyEvent.key);
                if (keyState == .blocked and keyEvent.event == .pressed) continue;
            }

            inputState.keyStates.upsert(keyEvent.key, if (keyEvent.event == .pressed) .pressed else .released);
            if (ac.KEY_EVENT_INFO == true) std.debug.print("Key {} pressed \n", .{keyEvent.key});
        }
        if (ac.KEY_EVENT_INFO == true) std.debug.print("KeyStates {}\n", .{inputState.keyStates.len});
    }

    pub fn mapAppEvents(inputState: *InputState, eventState: *EngineQueue) void {
        for (ac.keyMap) |assignment| {
            const actualKey = switch (assignment.device) {
                .keyboard => assignment.key,
                .mouse => assignment.key + SDL_KEY_MAX,
            };
            // If key is valid check if value at key is same as assignment state
            if (inputState.keyStates.isKeyUsed(actualKey) == true) {
                const keyState = inputState.keyStates.getByKey(actualKey);

                if (keyState == assignment.state) {
                    appendAppEvent(eventState, assignment.appEvent);
                    if (assignment.cycle == .oneTime) inputState.keyStates.upsert(actualKey, .released);
                    if (assignment.cycle == .oneBlock) inputState.keyStates.upsert(actualKey, .blocked);
                }
            }
        }
    }

    pub fn appendAppEvent(eventState: *EngineQueue, event: AppEvent) void {
        eventState.appEvents.append(event) catch |err| std.debug.print("EventManager.appendEvent failed: {}\n", .{err});
    }

    pub fn clearKeyEvents(inputState: *InputState) void {
        inputState.inputEvents.clear();
    }
};
