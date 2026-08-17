pub const RenderGraphData = struct {
    passLoad: @import("1_PassLoad.zig").PassLoadData = .{},
    outputLoad: @import("2_OutputLoad.zig").OutputLoadData = .{},
    composite: @import("3_Composite.zig").CompositeData = .{},
    resource: @import("4_Resource.zig").ResourceData = .{},
    graph: @import("5_Graph.zig").GraphData = .{},
    optimizer: @import("6_Optimizer.zig").OptimizerData = .{},
    lifetime: @import("7_Lifetime.zig").LifetimeData = .{},
    share: @import("8_Share.zig").ShareData = .{},
    sorter: @import("9_Sorter.zig").SorterData = .{},
};
