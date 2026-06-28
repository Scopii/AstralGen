const IdAdvanced = @import("../globalHelper.zig").IdAdvanced;
const Id = @import("../globalHelper.zig").Id;

pub const EntityId = Id(u32, .EntityId);

pub const WindowId = Id(u32, .WindowId);
pub const ViewportId = Id(u8, .ViewportId);

pub const ShaderId = Id(u8, .ShaderId);

pub const TexId = Id(u16, .TexId);
pub const BufId = Id(u16, .BufId);

pub const PassId = Id(u16, .PassId);
pub const BufPassId = Id(u16, .BufPassId);
pub const TexPassId = Id(u16, .TexPassId);

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
