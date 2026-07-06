const IdAdvanced = @import("../globalHelper.zig").IdAdvanced;
const Id = @import("../globalHelper.zig").Id;
const rc = @import("renderConfig.zig");
const sc = @import("shaderConfig.zig");

pub const EntityId = Id(u32, .EntityId, rc.ENTITY_MAX);

pub const WindowId = Id(u32, .WindowId, rc.MAX_WINDOWS);
pub const ViewportId = Id(u8, .ViewportId, rc.MAX_WINDOWS * 4);

pub const ShaderId = Id(u8, .ShaderId, sc.SHADER_MAX);

pub const TexId = Id(u16, .TexId, rc.TEX_MAX);
pub const BufId = Id(u16, .BufId, rc.BUF_MAX);

pub const PassId = Id(u16, .PassId, rc.PASS_MAX);
pub const BufPassId = Id(u16, .BufPassId, rc.BUF_MAX);
pub const TexPassId = Id(u16, .TexPassId, rc.TEX_MAX);
pub const ResPassId = Id(u16, .ResPassId, rc.RESOURCE_MAX);

// pub const TexPassId = IdAdvanced(u16, .TexPassId, &.{
//     .{ .RayMarchInputTex, null },
//     .{ .GridTex, null },
//     .{ .GridDepthTex, null },
//     .{ .DebugGridInputTex, null },
//     .{ .DebugGridOutputTex, null },
//     .{ .DebugGridDepthTex, null },
//     .{ .DebugGridDepthOutputTex, null },
//     .{ .PlaneTex, null },
//     .{ .PlaneDepthTex, null },
//     .{ .DebugPlaneInputTex, null },
//     .{ .DebugPlaneOutputTex, null },
//     .{ .DebugPlaneOutputFrustumViewTex, null },
//     .{ .DebugPlaneDepthTex, null },
//     .{ .DepthViewTex, null },
//     .{ .TestTileTex, null },
//     .{ .ImguiFontTex, null },
//     // .{ .Swapchain, null },
// });
