const RendererQueue = @import("../render/RendererQueue.zig").RendererQueue;
const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;
const RenderGraphData = @import("RenderGraphData.zig").RenderGraphData;
const EngineData = @import("../EngineData.zig").EngineData;
const rc = @import("../.configs/renderConfig.zig");
const UiData = @import("../ui/UiData.zig").UiData;
const ic = @import("../.configs/idConfig.zig");
const std = @import("std");
const TexPassId = ic.TexPassId;
const BufPassId = ic.BufPassId;
const BufId = ic.BufId;
const TexId = ic.TexId;

const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;

const PassSys = @import("1_Pass/PassSys.zig").PassSys;
const OutputSys = @import("0.5_Output/OutputSys.zig").OutputSys;
const AccessSys = @import("1.5_Access/AccessSys.zig").AccessSys;
const ResourceSys = @import("2_Resource/ResourceSys.zig").ResourceSys;
const DependancySys = @import("3_Dependancy/DependancySys.zig").DependancySys;
const GraphSys = @import("4_Graph/GraphSys.zig").GraphSys;
const OptimizerSys = @import("4.5_Optimizer/OptimizerSys.zig").OptimizerSys;
const LifetimeSys = @import("5_Lifetime/LifetimeSys.zig").LifetimeSys;
const MapperSys = @import("5.1_Mapper/MapperSys.zig").MapperSys;
const GroupSys = @import("5.4_Group/GroupSys.zig").GroupSys;
const SorterSys = @import("7_Sorter/SorterSys.zig").SorterSys;

pub const RenderGraphSys = struct {
    pub fn build(self: *RenderGraphData, data: *const EngineData) !void {
        const start0 = std.time.nanoTimestamp();
        try OutputSys.build(&self.output, &data.renderRegistry, data);
        if (rc.FRAME_GRAPH_TIMERS) std.debug.print("{d:.3} us: OutputSys\n", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start0)) / 1_000.0});

        const start1 = std.time.nanoTimestamp();
        try PassSys.build(&self.pass, &self.output, &data.renderRegistry, data);
        if (rc.FRAME_GRAPH_TIMERS) std.debug.print("{d:.3} us: PassSys\n", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start1)) / 1_000.0});

        const start2 = std.time.nanoTimestamp();
        try AccessSys.build(&self.access, &self.output, &data.renderRegistry);
        if (rc.FRAME_GRAPH_TIMERS) std.debug.print("{d:.3} us: AccessSys\n", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start2)) / 1_000.0});

        const start3 = std.time.nanoTimestamp();
        try ResourceSys.build(&self.resource, &self.access, &self.pass, &data.renderRegistry);
        if (rc.FRAME_GRAPH_TIMERS) std.debug.print("{d:.3} us: ResourceSys\n", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start3)) / 1_000.0});

        const start4 = std.time.nanoTimestamp();
        try DependancySys.build(&self.dependancy, &self.access, &data.renderRegistry);
        if (rc.FRAME_GRAPH_TIMERS) std.debug.print("{d:.3} us: DependancySys\n", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start4)) / 1_000.0});

        const start5 = std.time.nanoTimestamp();
        try GraphSys.build(&self.graph, &self.dependancy, &self.output, &data.renderRegistry);
        if (rc.FRAME_GRAPH_TIMERS) std.debug.print("{d:.3} us: GraphSys\n", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start5)) / 1_000.0});

        const start6 = std.time.nanoTimestamp();
        try OptimizerSys.build(&self.optimizer, &self.graph, &self.access, &self.resource, &data.renderRegistry);
        if (rc.FRAME_GRAPH_TIMERS) std.debug.print("{d:.3} us: OptimizerSys\n", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start6)) / 1_000.0});

        const start7 = std.time.nanoTimestamp();
        try LifetimeSys.assign(&self.lifetime, &self.optimizer, &self.access, &data.renderRegistry);
        if (rc.FRAME_GRAPH_TIMERS) std.debug.print("{d:.3} us: LifetimeSys\n", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start7)) / 1_000.0});

        const start8 = std.time.nanoTimestamp();
        try MapperSys.build(&self.mapper, &self.access, &self.resource, &self.lifetime, &self.optimizer, &data.renderRegistry);
        if (rc.FRAME_GRAPH_TIMERS) std.debug.print("{d:.3} us: MapperSys\n", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start8)) / 1_000.0});

        const start10 = std.time.nanoTimestamp();
        try GroupSys.build(&self.group, &self.mapper, &data.renderRegistry);
        if (rc.FRAME_GRAPH_TIMERS) std.debug.print("{d:.3} us: GroupSys\n", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start10)) / 1_000.0});

        const start12 = std.time.nanoTimestamp();
        try SorterSys.build(&self.sorter, &self.pass, &self.optimizer, &self.group, &data.renderRegistry);
        if (rc.FRAME_GRAPH_TIMERS) std.debug.print("{d:.3} us: SorterSys\n\n", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start12)) / 1_000.0});
    }
};
