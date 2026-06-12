const sc = @import("../../../.configs/shaderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const p = @import("../passImport.zig");

// OLD PASS

// pub fn Cull(
//     def: struct {
//         name: []const u8,
//         colorAtt: TextureLink,
//         depthAtt: TextureLink,
//         indirectBuf: BufferLink,
//         viewCam: BufferLink, // Maybe swapped
//         cullCam: BufferLink, // Maybe swapped
//     },
// ) PassDef {
//     return PassDef.MeshIndirect(.{
//         .name = def.name,
//         .outputTexId = def.colorAtt,
//         .execution = .{
//             .workgroups = .{ .x = 1, .y = 1, .z = 1 },
//             .indirectBuf = def.indirectBuf,
//             .indirectBufOffset = 0,
//             .mainTexId = def.colorAtt,
//         },
//         .mesh = sc.cullTestMesh,
//         .fragment = sc.cullTestFrag,
//         .bufUses = &.{
//             BufferUse.init(def.indirectBuf, .DrawIndirect, .IndirectRead, null),
//             BufferUse.init(def.viewCam, .Fragment, .UniformRead, 0),
//             BufferUse.init(def.cullCam, .Fragment, .UniformRead, 1),
//         },
//         .colorAtts = &.{AttachmentUse.init(def.colorAtt, .ColorAtt, .ColorAttReadWrite, .Attachment, .{ .color = .{ 0.0, 0.0, 0.0, 0.0 } })},
//         .depthAtt = AttachmentUse.init(def.depthAtt, .EarlyAndLateFragTest, .DepthStencilReadWrite, .Attachment, .{ .depthStencil = .{ .depth = 0.0, .stencil = 0 } }),
//         .renderState = .{
//             .depthTest = vk.VK_TRUE,
//             .depthWrite = vk.VK_TRUE,
//             .depthCompare = vk.VK_COMPARE_OP_GREATER,
//             .cullMode = vk.VK_CULL_MODE_NONE,
//         },
//     });
// }