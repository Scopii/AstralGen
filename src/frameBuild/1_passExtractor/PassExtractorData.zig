const RenderNode = @import("../../render/types/pass/PassDef.zig").RenderNode;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const rc = @import("../../.configs/renderConfig.zig");

// Step 1

pub const PassExtractorData = struct {
    passStrings: SimpleMap([]const u8, rc.PASS_MAX, u16, rc.PASS_MAX, 0) = .{}, // Maybe Rename Pass Size?
    renderNodes: LinkedMap(RenderNode, rc.PASS_MAX, u16, rc.PASS_MAX, 0) = .{}, // Node Size > Pass Size
};
