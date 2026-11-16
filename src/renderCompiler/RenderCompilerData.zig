const BarrierState = @import("../render/types/pass/RenderNode.zig").BarrierState;
const BarrierMask = @import("../render/types/pass/RenderNode.zig").BarrierMask;
const RenderNode = @import("../render/types/pass/RenderNode.zig").RenderNode;
const TextureState = @import("../render/types/res/Texture.zig").TextureState;
const LinkedIdMap = @import("../.structures/LinkedIdMap.zig").LinkedIdMap;
const UnionList = @import("../.structures/UnionList.zig").UnionList;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const WindowId = @import("../.configs/idConfig.zig").WindowId;
const TexId = @import("../.configs/idConfig.zig").TexId;
const BufId = @import("../.configs/idConfig.zig").BufId;
const rc = @import("../.configs/renderConfig.zig");

const UI_ESTIMATE = 1024;
const renderNodeCount = rc.PASS_MAX + rc.MAX_PASS_ATTRIBUTES + UI_ESTIMATE;

pub const RenderCompilerData = struct {
    pub const RenderNodeRing = UnionList(RenderNode, renderNodeCount);
    renderNodes: RenderNodeRing = .{},
    tempNodes: RenderNodeRing = .{}, // rc.PASS_MAX + rc.MAX_WINDOWS * 4 // rc.PASS_MAX * rc.MAX_PASS_ATTRIBUTES
    pushData: FixedList(u8, rc.PASS_MAX * 128) = .{}, // Still too small ??
    usedQueries: u8 = 0,

    bufStates: LinkedIdMap(BarrierState, rc.BUF_MAX * rc.MAX_IN_FLIGHT, BufId, rc.BUF_MAX * rc.MAX_IN_FLIGHT, 0) = .{},
    texStates: LinkedIdMap(TextureState, rc.TEX_MAX * rc.MAX_IN_FLIGHT, TexId, rc.TEX_MAX * rc.MAX_IN_FLIGHT, 0) = .{},

    swapchainStates: LinkedIdMap(TextureState, rc.MAX_WINDOWS, WindowId, 32 + rc.MAX_WINDOWS, 0) = .{},
    renderedSwapchains: FixedList(WindowId, rc.MAX_WINDOWS) = .{},

    mask: BarrierMask = .{},
    memBarrierUse: bool = false,
};
