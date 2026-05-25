const RenderNode = @import("../../render/types/pass/PassDef.zig").RenderNode;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;

// Step 7

pub const PassSorterData = struct {
    tempPasses: FixedList(u16, 128) = .{},
    tempBlits: FixedList(u16, 128) = .{},
    tempComposites: FixedList(u16, 128) = .{},
    tempUi: FixedList(u16, 128) = .{},

    sortedRenderNodes: FixedList(RenderNode, 128) = .{},
};
