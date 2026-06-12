const sc = @import("../../../.configs/shaderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const p = @import("../passImport.zig");

pub fn CompRayMarch(
    def: struct {
        name: p.PassEnum,
        outputTex: p.TextureLink,
        entityBuf: p.BufferLink,
        camBuf: p.BufferLink,
        readbackBuf: p.BufferLink,
        debugTex: p.TextureLink,
    },
) p.PassDef {
    return p.PassDef.Compute(.{
        .name = def.name,
        .outputTexId = def.outputTex.in,
        .execution = .{
            .workgroups = .{ .x = 8, .y = 8, .z = 1 },
            .outputTexDispatch = true,
        },
        .compute = sc.t1Comp,
        .bufUses = &.{
            p.BufferUse.init(def.entityBuf, .Compute, .StorageRead, 0),
            p.BufferUse.init(def.camBuf, .Compute, .UniformRead, 1),
            p.BufferUse.init(def.readbackBuf, .Compute, .StorageWrite, 3),
        },
        .texUses = &.{
            p.TextureUse.init(def.outputTex, .Compute, .StorageWrite, 2),
            p.TextureUse.init(def.debugTex, .Compute, .StorageRead, 4),
        },
    });
}
