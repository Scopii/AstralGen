const sc = @import("../../../.configs/shaderConfig.zig");
const vk = @import("../../../.modules/vk.zig").c;
const p = @import("../passImport.zig");

pub fn EditorGrid(
    def: struct {
        name: p.PassEnum,
        colorAtt: p.TextureLink,
        depthAtt: p.TextureLink,
        camBuf: p.BufferLink,
    },
) p.PassDef {
    return p.PassDef.Mesh(.{
        .name = def.name,
        .outputTexId = def.colorAtt.in,
        .execution = .{ .workgroups = .{ .x = 1, .y = 1, .z = 1 } },
        .mesh = sc.editorGridMesh,
        .fragment = sc.editorGridFrag,
        .bufUses = &.{
            p.BufferUse.init(def.camBuf, .Mesh, .UniformRead, 0),
        },
        .colorAtts = &.{p.AttachmentUse.init(def.colorAtt, .ColorAtt, .ColorAttReadWrite, .{ .color = .{ 0.0, 0.0, 0.0, 0.0 } })},
        .depthAtt = p.AttachmentUse.init(def.depthAtt, .EarlyAndLateFragTest, .DepthStencilReadWrite, null),
        .renderState = .{
            .colorBlend = vk.VK_FALSE,
            .depthTest = vk.VK_TRUE,
            .depthWrite = vk.VK_TRUE,
            .depthCompare = vk.VK_COMPARE_OP_GREATER,
            .cullMode = vk.VK_CULL_MODE_NONE,
        },
    });
}
