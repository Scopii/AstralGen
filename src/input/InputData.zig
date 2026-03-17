const LinkedMap = @import("../.structures/LinkedMap.zig").LinkedMap;
const KeyState = @import("../input/InputSys.zig").KeyState;

pub const SDL_KEY_MAX = 512;
pub const SDL_MOUSE_MAX = 24;

pub const InputData = struct {
    keyStates: LinkedMap(KeyState, SDL_KEY_MAX + SDL_MOUSE_MAX, c_uint, SDL_KEY_MAX + SDL_MOUSE_MAX, 0) = .{}, // 512 SDL Keys, 24 for Mouse
    mouseMoveX: f32 = 0,
    mouseMoveY: f32 = 0,

    camForward: bool = false,
    camBackward: bool = false,
    camLeft: bool = false,
    camRight: bool = false,
    camUp: bool = false,
    camDown: bool = false,
    camFovInc: bool = false,
    camFovDec: bool = false,
    toggleFullscreen: bool = false,
    closeApp: bool = false,
    toggleImgui: bool = false,
    speedMode: bool = false,

    pub fn resetMouseState(self: *InputData) void {
        self.mouseMoveX = 0;
        self.mouseMoveY = 0;
    }

    pub fn resetState(self: *InputData) void {
        self.camForward = false;
        self.camBackward = false;
        self.camLeft = false;
        self.camRight = false;
        self.camUp = false;
        self.camDown = false;
        self.camFovInc = false;
        self.camFovDec = false;
        self.toggleFullscreen = false;
        self.closeApp = false;
        self.toggleImgui = false;
        self.speedMode = false;
    }
};
