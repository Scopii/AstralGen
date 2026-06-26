const sc = @import("../../../.configs/shaderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const p = @import("../passImport.zig");

// OLD PASS

// pub const indirectCompTest: Pass = .{
//     .name = "IndirectCompTest",
//     .shaderIds = &.{sc.indirectComp.id},
//     .typ = Pass.createCompute(.{
//         .workgroups = .{ .x = 1, .y = 1, .z = 1 },
//     }),
//     .bufUses = &.{
//         BufferUse.init(indirectSB.id, .ComputeShader, .ShaderReadWrite, 0),
//     },
// };
