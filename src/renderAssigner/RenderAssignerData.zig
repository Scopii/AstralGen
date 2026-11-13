pub const PassTextureUpdate = @import("../renderAssigner/RenderAssignerQueue.zig").RenderAssignerEvent.PassTextureUpdate;
pub const PassBufferUpdate = @import("../renderAssigner/RenderAssignerQueue.zig").RenderAssignerEvent.PassBufferUpdate;
const TransientTexture = @import("../renderGraph/components.zig").TransientTexture;
const TransientBuffer = @import("../renderGraph/components.zig").TransientBuffer;
const UiNodeFill = @import("../render/types/pass/RenderNode.zig").UiNodeFill;
const SubResTexture = @import("../renderGraph/components.zig").SubResTexture;
const SubResBuffer = @import("../renderGraph/components.zig").SubResBuffer;
const LinkedIdMap = @import("../.structures/LinkedIdMap.zig").LinkedIdMap;
const ResRequest = @import("../renderGraph/components.zig").ResRequest;
const ManualBuf = @import("../renderGraph/components.zig").ManualBuf;
const ManualTex = @import("../renderGraph/components.zig").ManualTex;
const UnionList = @import("../.structures/UnionList.zig").UnionList;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const RingList = @import("../.structures/RingList.zig").RingList;
const TexInf = @import("../render/types/res/Texture.zig").TexInf;
const BufInf = @import("../render/types/res/Buffer.zig").BufInf;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const KeyPool = @import("../.structures/KeyPool.zig").KeyPool;
const TexId = @import("../.configs/idConfig.zig").TexId;
const BufId = @import("../.configs/idConfig.zig").BufId;
const UiDrawFill = UiNodeFill.UiDrawFill;
const rc = @import("../.configs/renderConfig.zig");

pub const MANUAL_STORAGE_COUNT = rc.MAX_IN_FLIGHT + 1;


pub const RenderAssignerData = struct {
    assignedFrames: u64 = 0,

    // Hardware Key Pools
    bufIdPool: KeyPool(u16, rc.BUF_MAX * rc.MAX_IN_FLIGHT) = .{},
    texIdPool: KeyPool(u16, rc.TEX_MAX * rc.MAX_IN_FLIGHT) = .{},

    // Transient Storage
    unusedTransientBufs: FixedList(TransientBuffer, rc.BUF_MAX) = .{},
    unusedTransientTexes: FixedList(TransientTexture, rc.TEX_MAX) = .{},

    usedTransientBufs: FixedList(TransientBuffer, rc.BUF_MAX) = .{},
    usedTransientTexes: FixedList(TransientTexture, rc.TEX_MAX) = .{},

    // Manuel Storage
    manualBufs: LinkedIdMap(ManualBuf, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    manualTexes: LinkedIdMap(ManualTex, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    manualSubBufs: LinkedIdMap(SubResBuffer, rc.BUF_MAX * rc.MAX_IN_FLIGHT, BufId, rc.BUF_MAX * rc.MAX_IN_FLIGHT, 0) = .{},
    manualSubTexes: LinkedIdMap(SubResTexture, rc.TEX_MAX * rc.MAX_IN_FLIGHT, TexId, rc.TEX_MAX * rc.MAX_IN_FLIGHT, 0) = .{},

    subBufDeletions: FixedList(struct { subBuf: BufId, deletionFrame: u64 }, rc.BUF_MAX * rc.MAX_IN_FLIGHT) = .{},
    subTexDeletions: FixedList(struct { subTex: TexId, deletionFrame: u64 }, rc.TEX_MAX * rc.MAX_IN_FLIGHT) = .{},

    bufUpdates: LinkedIdMap(PassBufferUpdate, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    texUpdates: LinkedIdMap(PassTextureUpdate, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    // Collective Storage Assignments
    bufAssigns: LinkedIdMap(BufId, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    texAssigns: LinkedIdMap(TexId, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    // Requests for Render Resource System
    requests: UnionList(ResRequest, rc.RESOURCE_MAX * rc.MAX_IN_FLIGHT) = .{},
};
