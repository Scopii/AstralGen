const sc = @import("../../../.configs/shaderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const p = @import("../passImport.zig");

pub fn FrustumView(
    def: struct {
        string: []const u8,
        colorAtt: p.TextureLink,
        depthAtt: p.TextureLink,
        renderCam: p.BufferLink,
        viewCam: p.BufferLink,
    },
) p.PassDef {
    return p.PassDef.Mesh(.{
        .name = def.string,
        .outputTexId = def.colorAtt.in,
        .execution = .{ .workgroups = .{ .x = 1, .y = 1, .z = 1 } },
        .mesh = sc.frustumMesh,
        .fragment = sc.quantFrag,
        .bufUses = &.{
            p.BufferUse.init(def.renderCam, .Mesh, .UniformRead, 0),
            p.BufferUse.init(def.viewCam, .Mesh, .UniformRead, 1),
        },
        .colorAtts = &.{p.AttachmentUse.init(def.colorAtt, .ColorAtt, .ColorAttReadWrite, .{ .color = .{ 0.0, 0.0, 0.0, 0.0 } })},
        .depthAtt = p.AttachmentUse.init(def.depthAtt, .EarlyAndLateFragTest, .DepthStencilReadWrite, null),
        .renderState = .{
            .depthTest = .False, // Depth Currently not in Use
            .depthWrite = .False, // Depth Currently not in Use
            .lineWidth = 2.0,
        },
    });
}
