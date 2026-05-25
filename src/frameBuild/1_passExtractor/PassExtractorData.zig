const RenderNode = @import("../../render/types/pass/PassDef.zig").RenderNode;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;

// Step 1

pub const PassExtractorData = struct {
    renderNodes: FixedList(RenderNode, 128) = .{},
};
