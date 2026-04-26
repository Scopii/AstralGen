const LinkedMap = @import("../.structures/LinkedMap.zig").LinkedMap;
const UiNode = @import("../render/types/pass/PassDef.zig").UiNode;
const rc = @import("../.configs/renderConfig.zig");

pub const UiData = struct {
    initialized: bool = false,
    baseContext: ?*anyopaque = null,
    fontAtlas: ?*anyopaque = null,
    contexts: LinkedMap(*anyopaque, rc.MAX_WINDOWS, u32, rc.MAX_WINDOWS + 32, 0) = .{},
    activeNodes: []UiNode = &.{},
};