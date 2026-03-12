const FixedList = @import("../structures/FixedList.zig").FixedList;
const LinkedMap = @import("../structures/LinkedMap.zig").LinkedMap;
const AppEvent = @import("../configs/appConfig.zig").AppEvent;

const KeyState = @import("../sys/EventSys.zig").KeyState;

pub const SDL_KEY_MAX = 512;
pub const SDL_MOUSE_MAX = 24;

pub const EventState = struct {
    keyStates: LinkedMap(KeyState, SDL_KEY_MAX + SDL_MOUSE_MAX, c_uint, SDL_KEY_MAX + SDL_MOUSE_MAX, 0) = .{}, // 512 SDL Keys, 24 for Mouse
    appEvents: FixedList(AppEvent, 127) = .{},
};
