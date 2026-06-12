const sc = @import("../../../.configs/shaderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const p = @import("../passImport.zig");

// OLD PASS

// pub fn CullComp(
//     def: struct {
//         name: []const u8,
//         indirectBuf: BufferLink,
//         entityBuf: BufferLink,
//     },
// ) PassDef {
//     return PassDef.Compute(.{
//         .name = def.name,
//         .outputTexId = null,
//         .execution = .{ .workgroups = .{ .x = 1, .y = 1, .z = 1 } },
//         .compute = sc.cullTestComp,
//         .bufUses = &.{
//             BufferUse.init(def.indirectBuf, .Compute, .ShaderReadWrite, 0),
//             BufferUse.init(def.entityBuf, .Compute, .ShaderRead, 1),
//         },
//     });
// }