const FixedList = @import("../.structures/FixedList.zig").FixedList;
const Pass = @import("../render/types/base/Pass.zig").Pass;
const RenderNode = @import("../render/types/base/Pass.zig").RenderNode;
const ViewportId = @import("../viewport/ViewportSys.zig").ViewportId;
const rc = @import("../.configs/renderConfig.zig");

pub const FrameBuildData = struct {
    passList: FixedList(RenderNode, 32) = .{},
};
