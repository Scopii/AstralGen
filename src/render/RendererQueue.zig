const RenderNode = @import("../render/types/pass/RenderNode.zig").RenderNode;
const LoadedShader = @import("../shader/LoadedShader.zig").LoadedShader;
const UnionList = @import("../.structures/UnionList.zig").UnionList;
const TexInf = @import("../render/types/res/Texture.zig").TexInf;
const BufInf = @import("../render/types/res/Buffer.zig").BufInf;
const TexId = @import("../.configs/idConfig.zig").TexId;
const BufId = @import("../.configs/idConfig.zig").BufId;
const Window = @import("../window/Window.zig").Window;
const vk = @import("../.modules/vk.zig").c;

pub const RendererQueue = UnionList(RendererEvent2, 127);

pub const RendererEvent2 = union(enum) {
    toggleGpuProfiling,

    addTexture: struct { texInf: TexInf, data: ?[]const u8 },
    addBuffer: struct { bufInf: BufInf, data: ?[]const u8 },
    updateBuffer: struct { bufId: BufId, data: []const u8 },
    updateBufferSegment: struct { bufId: BufId, data: []const u8, elementOffset: u32 },
    updateTexture: struct { texId: TexId, data: []const u8 },
    removeTexture: TexId,
    removeBuffer: BufId,
    updateWindowState: Window,

    addShader: LoadedShader,
};
