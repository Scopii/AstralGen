const TextureGroup = @import("../../frameBuild/components.zig").TextureGroup;
const TextureLink = @import("../../frameBuild/components.zig").TextureLink;
const BufferGroup = @import("../../frameBuild/components.zig").BufferGroup;
const BufferLink = @import("../../frameBuild/components.zig").BufferLink;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const SimpleMap = @import("../../.structures/SimpleMap.zig").SimpleMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const rc = @import("../../.configs/renderConfig.zig");

// Step 5.1

pub const MapperData = struct {
    // Last Frame Build Results
    lastBufGroupsTransient: BufGroupMap = .{},
    lastBufGroupsPersistent: BufGroupMap = .{},
    lastTexGroupsTransient: TexGroupMap = .{},
    lastTexGroupsPersistent: TexGroupMap = .{},

    // Temporary (For Buffers)
    bufPassIds: LinkedMap(BufPassId, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{},
    linkedBuffers: FixedList(BufferLink, rc.BUF_MAX) = .{},
    sharedBuffers: SimpleMap(BufPassId, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{},

    // Buffer Results
    bufMapTransient: LinkedMap(BufPassId, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{},
    bufGroupsTransient: BufGroupMap = .{},

    bufMapPersistent: LinkedMap(BufPassId, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{},
    bufGroupsPersistent: BufGroupMap = .{},

    // Temporary (For Textures)
    texPassIds: LinkedMap(TexPassId, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{},
    linkedTextures: FixedList(TextureLink, rc.TEX_MAX) = .{},
    sharedTextures: SimpleMap(TexPassId, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{},

    // Texture Results
    texMapTransient: LinkedMap(TexPassId, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{},
    texGroupsTransient: TexGroupMap = .{},

    texMapPersistent: LinkedMap(TexPassId, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{},
    texGroupsPersistent: TexGroupMap = .{},

    pub const BufGroupMap = LinkedMap(BufferGroup, rc.BUF_MAX, u16, rc.BUF_MAX, 0);
    pub const TexGroupMap = LinkedMap(TextureGroup, rc.TEX_MAX, u16, rc.TEX_MAX, 0);
};
