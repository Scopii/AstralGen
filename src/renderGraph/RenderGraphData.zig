pub const RenderGraphData = struct {
    pass: @import("1_Pass/PassData.zig").PassData = .{},
    access: @import("1.5_Access/AccessData.zig").AccessData = .{},
    resource: @import("2_Resource/ResourceData.zig").ResourceData = .{},
    dependancy: @import("3_Dependancy/DependancyData.zig").DependancyData = .{},
    graph: @import("4_Graph/GraphData.zig").GraphData = .{},
    optimizer: @import("4.5_Optimizer/OptimizerData.zig").OptimizerData = .{},
    lifetime: @import("5_Lifetime/LifetimeData.zig").LifetimeData = .{},
    mapper: @import("5.1_Mapper/MapperData.zig").MapperData = .{},
    group: @import("5.4_Group/GroupData.zig").GroupData = .{},
    comparator: @import("5.3_Comparator/ComparatorData.zig").ComparatorData = .{},
    sorter: @import("7_Sorter/SorterData.zig").SorterData = .{},
};
