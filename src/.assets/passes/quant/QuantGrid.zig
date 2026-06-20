const sc = @import("../../../.configs/shaderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const p = @import("../passImport.zig");

pub fn QuantGrid(
    def: struct {
        string: []const u8,
        colorAtt: p.TextureLink,
        depthAtt: p.TextureLink,
        indirectBuf: p.BufferLink,
        viewCam: p.BufferLink,
        renderCam: p.BufferLink,
    },
) p.PassDef {
    return p.PassDef.MeshIndirect(.{
        .name = def.string,
        .outputTexId = def.colorAtt.in,
        .execution = .{
            .workgroups = .{ .x = 1, .y = 1, .z = 1 },
            .indirectBuf = def.indirectBuf.in,
            .indirectBufOffset = 0,
        },
        .mesh = sc.quantGrid,
        .fragment = sc.quantFrag,
        .bufUses = &.{
            p.BufferUse.init(def.indirectBuf, .DrawIndirect, .IndirectRead, null),
            p.BufferUse.init(def.viewCam, .Fragment, .UniformRead, 0),
            p.BufferUse.init(def.renderCam, .Fragment, .UniformRead, 1),
        },
        .colorAtts = &.{p.AttachmentUse.init(def.colorAtt, .ColorAtt, .ColorAttReadWrite, .{ .color = .{ 0.0, 0.0, 0.0, 0.0 } })},
        .depthAtt = p.AttachmentUse.init(def.depthAtt, .EarlyAndLateFragTest, .DepthStencilReadWrite, .{ .depthStencil = .{ .depth = 0.0, .stencil = 0 } }),
        .renderState = .{
            .depthTest = vk.VK_TRUE,
            .depthWrite = vk.VK_TRUE,
            .depthCompare = vk.VK_COMPARE_OP_GREATER,
            .cullMode = vk.VK_CULL_MODE_NONE,
        },
    });
}
