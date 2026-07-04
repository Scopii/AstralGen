const PendingBufDeletion = @import("../../frameBuild/components.zig").PendingBufDeletion;
const PendingTexDeletion = @import("../../frameBuild/components.zig").PendingTexDeletion;
const TransientTexture = @import("../../frameBuild/components.zig").TransientTexture;
const TransientBuffer = @import("../../frameBuild/components.zig").TransientBuffer;
const TextureMeta = @import("../../render/types/res/TextureMeta.zig").TextureMeta;
const UpdateRequestEnum = @import("../../frameBuild/enums.zig").UpdateRequestEnum;
const TransientSlot = @import("../../frameBuild/components.zig").TransientSlot;
const BufferMeta = @import("../../render/types/res/BufferMeta.zig").BufferMeta;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const SimpleIdMap = @import("../../.structures/SimpleIdMap.zig").SimpleIdMap;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const KeyPool = @import("../../.structures/KeyPool.zig").KeyPool;
const TexId = @import("../../.configs/idConfig.zig").TexId;
const BufId = @import("../../.configs/idConfig.zig").BufId;
const rc = @import("../../.configs/renderConfig.zig");
const TexInf = TextureMeta.TexInf;
const BufInf = BufferMeta.BufInf;

// Step 6

pub const AssignerData = struct {
    // Key Pools
    bufIdPool: KeyPool(u16, rc.BUF_MAX) = .{},
    texIdPool: KeyPool(u16, rc.TEX_MAX) = .{},

    // Transient Storage
    unusedTransientBufs: FixedList(TransientBuffer, rc.BUF_MAX) = .{},
    unusedTransientTexes: FixedList(TransientTexture, rc.TEX_MAX) = .{},
    usedTransientSlots: FixedList(TransientSlot, rc.RESOURCE_MAX) = .{},

    // Persistent Storage
    rootBufPhysicalMap: LinkedIdMap(BufInf, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    rootTexPhysicalMap: LinkedIdMap(TexInf, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},
    pendingTexDeletions: FixedList(PendingTexDeletion, rc.TEX_MAX) = .{},
    pendingBufDeletions: FixedList(PendingBufDeletion, rc.BUF_MAX) = .{},

    // Manuel Storage
    manualBufs: LinkedIdMap(BufInf, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    manualTexes: LinkedIdMap(TexInf, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    // Collective Storage Assignments
    bufAssigns: LinkedIdMap(BufId, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    texAssigns: LinkedIdMap(TexId, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    // Update Requests after Resource Recreations
    updateRequests: LinkedMap(UpdateRequestEnum, 64, u16, 64, 0) = .{},
};
