pub const RenderGraphData = struct {
    passLoad: @import("1_PassLoad/PassLoad.zig").PassLoadData = .{},
    outputLoad: @import("2_OutputLoad/OutputLoad.zig").OutputLoadData = .{},
    composite: @import("3_Composite/Composite.zig").CompositeData = .{},
    resource: @import("4_Resource/Resource.zig").ResourceData = .{},
    graph: @import("5_Graph/Graph.zig").GraphData = .{},
    optimizer: @import("6_Optimizer/Optimizer.zig").OptimizerData = .{},
    lifetime: @import("7_Lifetime/Lifetime.zig").LifetimeData = .{},
    share: @import("8_Share/Share.zig").ShareData = .{},
    sorter: @import("9_Sorter/Sorter.zig").SorterData = .{},
};
