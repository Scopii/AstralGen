const sc = @import("../../../.configs/shaderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const p = @import("../passImport.zig");

// OLD PASS

// const gridTest: Pass = .{
//     .name = "GridTest",
//     .shaderIds = &.{ sc.gridTask.id, sc.gridMesh.id, sc.gridFrag.id },
//     .typ = Pass.createClassic(.{
//         .classicTyp = Pass.ClassicTyp.taskMeshData(.{ .workgroups = .{ .x = 1, .y = 1, .z = 1 } }),
//         .mainTexId = taskTex.id,
//         .colorAtts = &.{Attachment.init(taskTex.id, .ColorAtt, .ColorAttReadWrite, true)},
//     }),
//     .bufUses = &.{
//         BufferUse.init(cameraUB.id, .TaskShader, .ShaderRead, 0),
//     },
// };
