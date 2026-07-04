const CompositeNode = @import("../../render/types/pass/RenderNode.zig").CompositeNode;
const ViewportBlit = @import("../../render/types/pass/RenderNode.zig").ViewportBlit;
const SimpleIdMap = @import("../../.structures/SimpleIdMap.zig").SimpleIdMap;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 1

pub const PassData = struct {
    activePasses: LinkedIdMap(PassId, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
    passExtents: LinkedIdMap(struct { width: u32, height: u32 }, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
    composites: FixedList(CompositeNode, rc.MAX_WINDOWS * 4) = .{},
    blits: FixedList(ViewportBlit, rc.MAX_WINDOWS * 4) = .{},
};
