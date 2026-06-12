const sc = @import("../../../.configs/shaderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const p = @import("../passImport.zig");

pub fn QuantComp(
    def: struct {
        name: p.PassEnum,
        indirectBuf: p.BufferLink,
        entityBuf: p.BufferLink,
    },
) p.PassDef {
    return p.PassDef.Compute(.{
        .name = def.name,
        .outputTexId = null,
        .execution = .{
            .workgroups = .{ .x = 1, .y = 1, .z = 1 },
            .outputTexDispatch = false
        },
        .compute = sc.quantComp,
        .bufUses = &.{
            p.BufferUse.init(def.indirectBuf, .Compute, .StorageReadWrite, 0),
            p.BufferUse.init(def.entityBuf, .Compute, .StorageRead, 1),
        },
    });
}
