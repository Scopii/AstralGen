const sc = @import("../../../.configs/shaderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const p = @import("../passImport.zig");

// pub fn QuantComp(
//     def: struct {
//         string: []const u8,
//         indirectBuf: p.BufferLink,
//         entityBuf: p.BufferLink,
//     },
// ) p.PassDef {
//     return p.PassDef.Compute(.{
//         .name = def.string,
//         .outputTexId = null,
//         .execution = .{ .workgroups = .{ .x = 1, .y = 1, .z = 1 }, .outputTexDispatch = false },
//         .compute = sc.quantComp,
//         .bufUses = &.{
//             p.BufferUse.init(def.indirectBuf, .Compute, .StorageReadWrite, 0),
//             p.BufferUse.init(def.entityBuf, .Compute, .StorageRead, 1),
//         },
//     });
// }

pub const quantCompPass = p.PassDefinition.init(.{
    .name = "QuantComp",
    .outputTex = null,
    .execution = .execCompute(.{ .groupX = 1, .groupY = 1, .groupZ = 1, .outputTexDispatch = false }),
    .attributes = &.{
        p.PassAttrib.shader(sc.quantComp),
        //
        p.PassAttrib.buf(.{ .in = "QuantIndirectInputSB", .out = "QuantIndirectOutputSB" }, .Compute, .StorageReadWrite, 0),
        p.PassAttrib.buf(.{ .in = "EntitySB" }, .Compute, .StorageRead, 1),
    },
});
