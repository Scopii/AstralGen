const RenderNode = @import("../render/types/pass/PassDef.zig").RenderNode;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const rc = @import("../.configs/renderConfig.zig");

pub const FrameBuildData = struct {
    passList: FixedList(RenderNode, 64) = .{},
};
