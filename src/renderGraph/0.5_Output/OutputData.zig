const CompositeNode = @import("../../render/types/pass/RenderNode.zig").CompositeNode;
const PassAccessRange = @import("../../renderGraph/components.zig").PassAccessRange;
const SimpleIdMap = @import("../../.structures/SimpleIdMap.zig").SimpleIdMap;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 0.5

pub const OutputData = struct {
    texInputs: FixedList(TexPassId, rc.PASS_MAX * rc.TEX_MAX) = .{},
    bufInputs: FixedList(BufPassId, rc.PASS_MAX * rc.BUF_MAX) = .{},

    texInputRanges: LinkedIdMap(PassAccessRange, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
    bufInputRanges: LinkedIdMap(PassAccessRange, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},

    texProducer: LinkedIdMap(PassId, rc.PASS_MAX * rc.TEX_MAX, TexPassId, rc.PASS_MAX * rc.TEX_MAX, 0) = .{},
    bufProducer: LinkedIdMap(PassId, rc.PASS_MAX * rc.BUF_MAX, BufPassId, rc.PASS_MAX * rc.BUF_MAX, 0) = .{},

    pendingPasses: FixedList(PassId, rc.PASS_MAX) = .{},

    // Results
    activePasses: LinkedIdMap(PassId, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
    passExtents: LinkedIdMap(struct { width: u32, height: u32 }, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
};
