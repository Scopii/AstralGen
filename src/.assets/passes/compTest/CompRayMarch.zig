const sc = @import("../../../.configs/shaderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const p = @import("../passImport.zig");

// pub fn CompRayMarch(
//     def: struct {
//         string: []const u8,
//         outputTex: p.TextureLink,
//         entityBuf: p.BufferLink,
//         camBuf: p.BufferLink,
//         readbackBuf: p.BufferLink,
//         debugTex: p.TextureLink,
//     },
// ) p.PassDef {
//     return p.PassDef.Compute(.{
//         .name = def.string,
//         .outputTexId = def.outputTex.in,
//         .execution = .{
//             .workgroups = .{ .x = 8, .y = 8, .z = 1 },
//             .outputTexDispatch = true,
//         },
//         .compute = sc.t1Comp,
//         .bufUses = &.{
//             p.BufferUse.init(def.entityBuf, .Compute, .StorageRead, 0),
//             p.BufferUse.init(def.camBuf, .Compute, .UniformRead, 1),
//             p.BufferUse.init(def.readbackBuf, .Compute, .StorageWrite, 3),
//         },
//         .texUses = &.{
//             p.TextureUse.init(def.outputTex, .Compute, .StorageWrite, 2),
//             p.TextureUse.init(def.debugTex, .Compute, .StorageRead, 4),
//         },
//     });
// }

pub const compRayMarchPass = p.PassDefinition.init(.{
    .name = "CompRayMarch",
    .outputTex = "RayMarchInputTex",
    .execution = .execCompute(.{ .groupX = 8, .groupY = 8, .groupZ = 1, .outputTexDispatch = true }),
    .attributes = &.{
        p.PassAttrib.shader(sc.t1Comp),
        //
        p.PassAttrib.buf(.{ .in = "EntitySB" }, .Compute, .StorageRead, 0),
        p.PassAttrib.buf(.{ .in = "MainCamUB" }, .Compute, .UniformRead, 1),
        p.PassAttrib.buf(.{ .in = "ReadbackSB" }, .Compute, .StorageWrite, 3),
        p.PassAttrib.tex(.{ .in = "RayMarchInputTex", .out = "RayMarchOutputTex" }, .Compute, .StorageWrite, 2),
        p.PassAttrib.tex(.{ .in = "TestTileTex" }, .Compute, .StorageRead, 4),
    },
});
