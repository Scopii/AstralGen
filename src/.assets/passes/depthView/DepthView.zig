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
    .passAttributes = &.{
        p.PassAttrib.exec(.{
            .compute = .{
                .workgroups = .{ .x = 8, .y = 8, .z = 1 },
                .outputTexDispatch = true,
            },
        }),
        //
        p.PassAttrib.shader(sc.depthViewComp),
        //
        p.PassAttrib.buf(.{ .in = "MainCamUB" }, .Compute, .UniformRead, 3),
        p.PassAttrib.tex(.{ .in = "DepthViewTex" }, .Compute, .StorageWrite, 0),
        p.PassAttrib.tex(.{ .in = "DebugGridDepthOutputTex" }, .Compute, .SampledRead, 1),
    },
});
