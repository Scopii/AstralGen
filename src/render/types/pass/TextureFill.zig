const TextureStringLink = @import("../../../frameBuild/components.zig").TextureStringLink;
const Texture = @import("../res/Texture.zig").Texture;
const vhE = @import("../../help/Enums.zig");

const TexId = @import("../res/TextureMeta.zig").TextureMeta.TexId;

pub const TextureFill = struct {
    texId: TexId,
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    layout: vhE.ImageLayout,
    descUse: vhE.TexDescriptor,
    shaderSlot: ?u32 = null,

    pub const TextureUseKind = enum { SampledRead, StorageRead, StorageWrite, StorageReadWrite };

    pub fn init(texId: TexId, stage: vhE.PipeStage, texUseKind: TextureUseKind, shaderSlot: ?u8) TextureFill {
        const layout: vhE.ImageLayout = switch (texUseKind) {
            .SampledRead => .ReadOnly,
            .StorageRead, .StorageWrite, .StorageReadWrite => .General,
        };

        const descUse: vhE.TexDescriptor = switch (texUseKind) {
            .SampledRead => .Sampled,
            .StorageRead, .StorageWrite, .StorageReadWrite => .Storage,
        };

        const access: vhE.PipeAccess = switch (texUseKind) {
            .SampledRead => .SampledRead,
            .StorageRead => .StorageRead,
            .StorageWrite => .StorageWrite,
            .StorageReadWrite => .storageReadWrite,
        };

        return .{
            .texId = texId,
            .stage = stage,
            .access = access,
            .layout = layout,
            .shaderSlot = if (shaderSlot) |slot| slot else null,
            .descUse = descUse,
        };
    }

    pub fn getNeededState(self: *const TextureFill) Texture.TextureState {
        return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
    }
};
