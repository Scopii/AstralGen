const CompositeNode = @import("../../render/types/pass/RenderNode.zig").CompositeNode;
const ViewportBlit = @import("../../render/types/pass/RenderNode.zig").ViewportBlit;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 1

pub const PassData = struct {
    activePasses: SimpleMap(PassId, rc.PASS_MAX, u16, rc.PASS_MAX, 0) = .{},
    passExtents: SimpleMap(struct { width: u32, height: u32 }, rc.PASS_MAX, u16, rc.PASS_MAX, 0) = .{},
    composites: FixedList(CompositeNode, rc.MAX_WINDOWS * 4) = .{},
    blits: FixedList(ViewportBlit, rc.MAX_WINDOWS * 4) = .{},
};
