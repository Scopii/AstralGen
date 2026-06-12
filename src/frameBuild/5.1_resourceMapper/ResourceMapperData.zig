const TextureGroup = @import("../../frameBuild/components.zig").TextureGroup;
const TextureLink = @import("../../frameBuild/components.zig").TextureLink;
const BufferGroup = @import("../../frameBuild/components.zig").BufferGroup;
const BufferLink = @import("../../frameBuild/components.zig").BufferLink;
const LinkedMap = @import("../../.structures/LinkedMap.zig").LinkedMap;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const TextureEnum = @import("../../frameBuild/enums.zig").TextureEnum;
const BufferEnum = @import("../../frameBuild/enums.zig").BufferEnum;
const rc = @import("../../.configs/renderConfig.zig");

// Step 5.1

pub const ResourceMapperData = struct {
    // Last Frame Build Results
    lastBufGroupsTransient: BufGroupMap = .{},
    lastBufGroupsPersistent: BufGroupMap = .{},
    lastTexGroupsTransient: TexGroupMap = .{},
    lastTexGroupsPersistent: TexGroupMap = .{},

    // Temporary (For Buffers)
    bufferEnums: LinkedMap(BufferEnum, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{},
    linkedBuffers: FixedList(BufferLink, rc.BUF_MAX) = .{},
    allSharedBuffers: LinkedMap(BufferEnum, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{},

    // Buffer Results
    bufMapTransient: LinkedMap(BufferEnum, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{},
    bufGroupsTransient: BufGroupMap = .{},

    bufMapPersistent: LinkedMap(BufferEnum, rc.BUF_MAX, u16, rc.BUF_MAX, 0) = .{},
    bufGroupsPersistent: BufGroupMap = .{},

    // Temporary (For Textures)
    textureEnums: LinkedMap(TextureEnum, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{},
    linkedTextures: FixedList(TextureLink, rc.TEX_MAX) = .{},
    allSharedTextures: LinkedMap(TextureEnum, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{},

    // Texture Results
    texMapTransient: LinkedMap(TextureEnum, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{},
    texGroupsTransient: TexGroupMap = .{},

    texMapPersistent: LinkedMap(TextureEnum, rc.TEX_MAX, u16, rc.TEX_MAX, 0) = .{},
    texGroupsPersistent: TexGroupMap = .{},

    pub const BufGroupMap = LinkedMap(BufferGroup, rc.BUF_MAX, u16, rc.BUF_MAX, 0);
    pub const TexGroupMap = LinkedMap(TextureGroup, rc.TEX_MAX, u16, rc.TEX_MAX, 0);
};
