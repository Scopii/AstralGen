const InputState = @import("../state/InputState.zig").InputState;
const sdl = @import("../modules/sdl.zig").c;
const SDL_KEY_MAX = @import("../sys/EventSys.zig").SDL_KEY_MAX;
const std = @import("std");
const KeyEvent = @import("../sys/EventSys.zig").KeyEvent;

pub const InputSys = struct {
    pub fn processKeyEvent(inputState: *InputState, event: *const sdl.SDL_Event) void {
        var keyEvent: KeyEvent = undefined;

        switch (event.type) {
            sdl.SDL_EVENT_MOUSE_BUTTON_DOWN => keyEvent = .{ .key = @as(c_uint, event.button.button) + SDL_KEY_MAX, .event = .pressed },
            sdl.SDL_EVENT_MOUSE_BUTTON_UP => keyEvent = .{ .key = @as(c_uint, event.button.button) + SDL_KEY_MAX, .event = .released },
            sdl.SDL_EVENT_KEY_DOWN => keyEvent = .{ .key = event.key.scancode, .event = .pressed },
            sdl.SDL_EVENT_KEY_UP => keyEvent = .{ .key = event.key.scancode, .event = .released },
            else => {
                std.debug.print("Key Event {} could not be processed! \n", .{event.type});
                return;
            },
        }
        inputState.inputEvents.append(keyEvent) catch |err| std.debug.print("WindowManager: mouseButtonEvents append failed {}\n", .{err});
    }

    pub fn processMouseEvent(inputState: *InputState, event: *const sdl.SDL_Event) void {
        inputState.mouseMoveX += event.motion.xrel;
        inputState.mouseMoveY += event.motion.yrel;
    }

    pub fn getKeyEvents(inputState: *InputState) []KeyEvent {
        return inputState.inputEvents.slice();
    }

    pub fn clearKeyEvents(inputState: *InputState) void{
        inputState.inputEvents.clear();
    }
};
