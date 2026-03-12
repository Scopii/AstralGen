const FixedList = @import("../structures/FixedList.zig").FixedList;
const LinkedMap = @import("../structures/LinkedMap.zig").LinkedMap;
const Window = @import("../types/Window.zig").Window;
const sdl = @import("../modules/sdl.zig").c;
const vk = @import("../modules/vk.zig").c;
const MAX_WINDOWS = @import("../configs/renderConfig.zig").MAX_WINDOWS;

pub const WindowState = struct {
    windows: LinkedMap(Window, MAX_WINDOWS, u32, 32 + MAX_WINDOWS, 0) = .{},
    mainWindow: ?*Window = null,
    changedWindows: FixedList(Window, MAX_WINDOWS) = .{},
    openWindows: u8 = 0,
    appExit: bool = false,
    windowProps: sdl.SDL_PropertiesID = 0,
    uiActive: bool = false,
};