const FixedList = @import("../.structures/FixedList.zig").FixedList;
const LinkedMap = @import("../.structures/LinkedMap.zig").LinkedMap;
const UiNode = @import("../render/types/pass/RenderNode.zig").UiNode;
const rc = @import("../.configs/renderConfig.zig");

pub const UiData = struct {
    initialized: bool = false,
    baseContext: ?*anyopaque = null,
    fontAtlas: ?*anyopaque = null,
    contexts: LinkedMap(*anyopaque, rc.MAX_WINDOWS, u32, rc.MAX_WINDOWS + 32, 0) = .{},

    uiNodes: UiNodes = .{},
    uiDraws: UiDraws = .{},
    pub const UiNodes = FixedList(UiNode, 64);
    pub const UiDraws = FixedList(UiNode.UiDraw, 1024);
};
