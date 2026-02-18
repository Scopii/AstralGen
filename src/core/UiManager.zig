const LinkedMap = @import("../structures/LinkedMap.zig").LinkedMap;
const std = @import("std");
const zm = @import("zmath");

const ImGuiMan = @import("../vulkan/sys/ImGuiMan.zig").ImGuiMan;
const zgui = @import("zgui");
const sdl = @import("../modules/sdl.zig").c;

// pub const Alignment = enum { left, right, top, bot, center, topRight, topLeft, botRight, botLeft, none };
// pub const Ruleset = enum { rightRow, leftRow, topColumn, bottomColumn, none };

pub const UiManager = struct {
    uiActive: bool = false,

    pub fn init() !UiManager {
        return .{};
    }

    pub fn toggleUi(self: *UiManager) void {
        if (self.uiActive == true) self.uiActive = false else self.uiActive = true;
    }
};
