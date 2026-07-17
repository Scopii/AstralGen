const sc = @import("../../../.configs/shaderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const p = @import("../passImport.zig");

// pub fn DepthView(def: struct {
//     string: []const u8,
//     outputTex: p.TextureLink,
//     depthTex: p.TextureLink,
//     camBuf: p.BufferLink,
// }) p.PassDef {
//     return p.PassDef.Compute(.{
//         .name = def.string,
//         .outputTexId = def.outputTex.in,
//         .execution = .{
//             .workgroups = .{ .x = 8, .y = 8, .z = 1 },
//             .outputTexDispatch = true,
//         },
//         .compute = sc.depthViewComp,
//         .bufUses = &.{
//             p.BufferUse.init(def.camBuf, .Compute, .UniformRead, 3),
//         },
//         .texUses = &.{
//             p.TextureUse.init(def.outputTex, .Compute, .StorageWrite, 0),
//             p.TextureUse.init(def.depthTex, .Compute, .SampledRead, 1),
//         },
//     });
// }

pub const depthViewPass = p.PassDefinition.init(.{
    .name = "DepthView",
    .outputTex = "DepthViewTex",
    .renderScaling = 2.0,
    .execution = .execCompute(.{ .groupX = 8, .groupY = 8, .groupZ = 1, .outputTexDispatch = true }),
    .attributes = &.{
        p.PassAttrib.shader(sc.depthViewComp),
        //
        p.PassAttrib.buf(.{ .in = "MainCamUB" }, .Compute, .UniformRead, 3),
        p.PassAttrib.tex(.{ .in = "DepthViewTex" }, .Compute, .StorageWrite, 0),
        p.PassAttrib.tex(.{ .in = "DebugGridDepthOutputTex" }, .Compute, .SampledRead, 1),
        //
        p.PassAttrib.texDep(.{ .in = "DebugGridOutputTex" }),
        p.PassAttrib.texDep(.{ .in = "DebugPlaneOutputFrustumViewTex" }),
        p.PassAttrib.texDep(.{ .in = "DebugPlaneDepthTex" }),
    },
});
