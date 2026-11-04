const TransientTexture = @import("../renderGraph/components.zig").TransientTexture;
const TransientBuffer = @import("../renderGraph/components.zig").TransientBuffer;
const TextureMeta = @import("../render/types/res/TextureMeta.zig").TextureMeta;
const UiNodeFill = @import("../render/types/pass/RenderNode.zig").UiNodeFill;
const BufferMeta = @import("../render/types/res/BufferMeta.zig").BufferMeta;
const LinkedIdMap = @import("../.structures/LinkedIdMap.zig").LinkedIdMap;
const ResRequest = @import("../renderGraph/components.zig").ResRequest;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const KeyPool = @import("../.structures/KeyPool.zig").KeyPool;
const TexId = @import("../.configs/idConfig.zig").TexId;
const BufId = @import("../.configs/idConfig.zig").BufId;
const UiDrawFill = UiNodeFill.UiDrawFill;
const rc = @import("../.configs/renderConfig.zig");
const TexInf = TextureMeta.TexInf;
const BufInf = BufferMeta.BufInf;

pub const MANUAL_STORAGE_COUNT = rc.MAX_IN_FLIGHT + 1;

pub const RenderAssignerManualData = struct {
    // Manuel Storage
    manualBufs: LinkedIdMap(BufInf, rc.BUF_MAX, BufPassId, rc.BUF_MAX * rc.MAX_IN_FLIGHT, 0) = .{},
    manualTexes: LinkedIdMap(TexInf, rc.TEX_MAX, TexPassId, rc.TEX_MAX * rc.MAX_IN_FLIGHT, 0) = .{},
};

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
    manualStorages: [MANUAL_STORAGE_COUNT]RenderAssignerManualData = @splat(.{}),

    manualBufRotated: LinkedIdMap(bool, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    manualTexRotated: LinkedIdMap(bool, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    manualBufCycle: LinkedIdMap(u8, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    manualTexCycle: LinkedIdMap(u8, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    // Collective Storage Assignments
    bufAssigns: LinkedIdMap(BufId, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    texAssigns: LinkedIdMap(TexId, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    // Requests for Render Resource System
    requests: FixedList(ResRequest, rc.BUF_MAX + rc.TEX_MAX * rc.MAX_IN_FLIGHT) = .{},
};
