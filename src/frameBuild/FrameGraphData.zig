pub const FrameGraphData = struct {
    passExtractor: @import("1_passExtractor/PassExtractorData.zig").PassExtractorData = .{},
    resourceExtractor: @import("2_resourceExtractor/ResourceExtractorData.zig").ResourceExtractorData = .{},
    dependancyExtractor: @import("3_dependancyExtractor/DependancyExtractorData.zig").DependancyExtractorData = .{},
    graphExtractor: @import("4_graphExtractor/GraphExtractorData.zig").GraphExtractorData = .{},
    GraphOptimizerData: @import("4.5_graphOptimizer/GraphOptimizerData.zig").GraphOptimizerData = .{},
    lifetimeExtractor: @import("5_lifetimeExtractor/LifetimeExtractorData.zig").LifetimeExtractorData = .{},
    resourceMapper: @import("5.1_resourceMapper/ResourceMapperData.zig").ResourceMapperData = .{},
    lifetimeMerger: @import("5.2_lifetimeMerger/LifetimeMergerData.zig").LifetimeMergerData = .{},
    groupMerger: @import("5.4_groupMerger/GroupMergerData.zig").GroupMergerData = .{},
    mappingComparator: @import("5.3_mappingComparator/MappingComparatorData.zig").MappingComparatorData = .{},
    resourceAssigner: @import("6_resourceAssigner/ResourceAssignerData.zig").ResourceAssignerData = .{},
    passSorter: @import("7_passSorter/PassSorterData.zig").PassSorterData = .{},
};
