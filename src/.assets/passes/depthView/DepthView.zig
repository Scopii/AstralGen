const sc = @import("../../../.configs/shaderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const p = @import("../passImport.zig");

pub fn DepthView(def: struct {
    string: []const u8,
    outputTex: p.TextureLink,
    depthTex: p.TextureLink,
    camBuf: p.BufferLink,
}) p.PassDef {
    return p.PassDef.Compute(.{
        .name = def.string,
        .outputTexId = def.outputTex.in,
        .execution = .{
            .workgroups = .{ .x = 8, .y = 8, .z = 1 },
            .outputTexDispatch = true,
        },
        .compute = sc.depthViewComp,
        .bufUses = &.{
            p.BufferUse.init(def.camBuf, .Compute, .UniformRead, 3),
        },
        .texUses = &.{
            p.TextureUse.init(def.outputTex, .Compute, .StorageWrite, 0),
            p.TextureUse.init(def.depthTex, .Compute, .SampledRead, 1),
        },
    });
}

pub const depthViewPass = p.PassDefinition.init(.{
    .name = "DepthView",
    .execution = .{
        .compute = .{
            .workgroups = .{ .x = 8, .y = 8, .z = 1 },
            .outputTexDispatch = true,
        },
    },
    .outputTex = "DepthViewTex",
    .passAttributes = &.{
        p.PassAttrib{ .shaderInf = sc.depthViewComp },
        p.PassAttrib{ .bufSlot = p.BufferSlot.init(.{ .in = "MainCamUB" }, .Compute, .UniformRead, 3) },
        p.PassAttrib{ .texSlot = p.TextureSlot.init(.{ .in = "DepthViewTex" }, .Compute, .StorageWrite, 0) },
        p.PassAttrib{ .texSlot = p.TextureSlot.init(.{ .in = "DebugGridDepthOutputTex" }, .Compute, .SampledRead, 1) },
    },
});
