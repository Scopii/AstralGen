const RenderNode = @import("../../render/types/pass/PassDef.zig").RenderNode;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const rc = @import("../../.configs/renderConfig.zig");

// Step 1

pub const PassExtractorData = struct {
    renderNodes: FixedList(RenderNode, rc.PASS_MAX) = .{},
    
};
