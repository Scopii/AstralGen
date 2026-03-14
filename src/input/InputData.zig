const LinkedMap = @import("../.structures/LinkedMap.zig").LinkedMap;
// const KeyEvent = @import("../input/InputSys.zig").KeyEvent;
const KeyState = @import("../input/InputSys.zig").KeyState;

pub const SDL_KEY_MAX = 512;
pub const SDL_MOUSE_MAX = 24;

pub const InputData = struct {
    keyStates: LinkedMap(KeyState, SDL_KEY_MAX + SDL_MOUSE_MAX, c_uint, SDL_KEY_MAX + SDL_MOUSE_MAX, 0) = .{}, // 512 SDL Keys, 24 for Mouse
    mouseMoveX: f32 = 0,
    mouseMoveY: f32 = 0,
};
