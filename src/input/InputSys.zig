const RendererQueue = @import("../render/RendererQueue.zig").RendererQueue;
const WindowQueue = @import("../window/WindowQueue.zig").WindowQueue;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const LinkedMap = @import("../.structures/LinkedMap.zig").LinkedMap;
const InputQueue = @import("../input/InputQueue.zig").InputQueue;
const AppEvent = @import("../.configs/appConfig.zig").AppEvent;
const InputData = @import("../input/InputData.zig").InputData;
const ac = @import("../.configs/appConfig.zig");
const sdl = @import("../.modules/sdl.zig").c;
const std = @import("std");

pub const KeyState = enum { pressed, released, blocked };
pub const KeyEvent = struct { key: c_uint, event: KeyState };

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
    pub fn update(inputData: *InputData, inputQueue: *InputQueue) void {
        inputData.resetMouseState();

        for (inputQueue.get()) |inputEvent| {
            switch (inputEvent) {
                .keyEvent => |keyEvent| {
                    if (inputData.keyStates.isIndexValid(keyEvent.key) == false) {
                        std.debug.print("Key {} Invalid\n", .{keyEvent.key});
                        continue;
                    }

                    if (inputData.keyStates.isKeyUsed(keyEvent.key)) {
                        const keyState = inputData.keyStates.getByKey(keyEvent.key);
                        if (keyState == .blocked and keyEvent.event == .pressed) continue;
                    }

                    inputData.keyStates.upsert(keyEvent.key, if (keyEvent.event == .pressed) .pressed else .released);
                    if (ac.KEY_EVENT_INFO == true) std.debug.print("Key {} pressed \n", .{keyEvent.key});
                },
                .mouseMove => |mouseMove| {
                    inputData.mouseMoveX += mouseMove.x;
                    inputData.mouseMoveY += mouseMove.y;
                },
            }
        }
        inputQueue.clear();
        if (ac.KEY_EVENT_INFO == true) std.debug.print("KeyStates {}\n", .{inputData.keyStates.len});
    }

    pub fn convert(inputData: *InputData, rendererQueue: *RendererQueue) void {
        inputData.resetState();

        for (ac.keyMap) |assignment| {
            const actualKey = switch (assignment.device) {
                .keyboard => assignment.key,
                .mouse => assignment.key + SDL_KEY_MAX,
            };
            // If key is valid check if value at key is same as assignment state
            if (inputData.keyStates.isKeyUsed(actualKey) == true) {
                const keyState = inputData.keyStates.getByKey(actualKey);

                if (keyState == assignment.state) {

                    // Append Events for Queues:
                    switch (assignment.appEvent) {
                        .camForward => inputData.camForward = true,
                        .camBackward => inputData.camBackward = true,
                        .camLeft => inputData.camLeft = true,
                        .camRight => inputData.camRight = true,
                        .camUp => inputData.camUp = true,
                        .camDown => inputData.camDown = true,
                        .camFovIncrease => inputData.camFovInc = true,
                        .camFovDecrease => inputData.camFovDec = true,

                        .toggleFullscreen => inputData.toggleFullscreen = true,
                        .closeApp => inputData.closeApp = true,
                        .toggleImgui => {
                            inputData.toggleImgui = true;
                        },
                        .toggleGpuProfiling => {
                            rendererQueue.append(.toggleGpuProfiling);
                        },
                        .speedMode => inputData.speedMode = true,
                    }

                    if (assignment.cycle == .oneTime) inputData.keyStates.upsert(actualKey, .released);
                    if (assignment.cycle == .oneBlock) inputData.keyStates.upsert(actualKey, .blocked);
                }
            }
        }
    }
};
