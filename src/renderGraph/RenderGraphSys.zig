const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const ViewportData = @import("../viewport/ViewportData.zig").ViewportData;
const RenderGraphData = @import("RenderGraphData.zig").RenderGraphData;
const WindowData = @import("../window/WindowData.zig").WindowData;
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

const PassLoadSys = @import("1_PassLoad.zig").PassLoadSys;
const OutputLoadSys = @import("2_OutputLoad.zig").OutputLoadSys;
const CompositeSys = @import("5.2_Composite.zig").CompositeSys;
const DependencySys = @import("3.5_Dependency.zig").DependencySys;
const GraphSys2 = @import("5_Graph.zig").GraphSys;
const ResourceSys2 = @import("5.5_Resource.zig").ResourceSys;
const OptimizerSys2 = @import("6_Optimizer.zig").OptimizerSys;
const LifetimeSys2 = @import("7_Lifetime.zig").LifetimeSys;
const ShareSys2 = @import("8_Share.zig").ShareSys;
const SorterSys2 = @import("9_Sorter.zig").SorterSys;

pub const RenderGraphSys = struct {
    pub fn activateManuelPass(self: *RenderGraphData, renderRegistry: *const RenderRegistryData, name: []const u8) !void {
        const passId = try renderRegistry.getPassId(name);
        if (self.manuelPasses.isKeyUsed(passId) == false) self.manuelPasses.insert(passId, passId);
    }

    pub fn disableManuelPass(self: *RenderGraphData, renderRegistry: *const RenderRegistryData, name: []const u8) !void {
        const passId = try renderRegistry.getPassId(name);
        if (self.manuelPasses.isKeyUsed(passId) == true) self.manuelPasses.remove(passId);
    }

    pub fn build(self: *RenderGraphData, renderRegistry: *const RenderRegistryData, viewportData: *const ViewportData, windowData: *const WindowData) !void {
        const start0 = std.time.nanoTimestamp();
        try PassLoadSys.build(&self.passLoad, renderRegistry);
        if (rc.FRAME_GRAPH_TIMERS) std.debug.print("{d:.3} us: PassLoadSys\n", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start0)) / 1_000.0});

        const start1 = std.time.nanoTimestamp();
        try OutputLoadSys.build(&self.outputLoad, &self.passLoad, renderRegistry, viewportData, self.manuelPasses.getConstItems());
        if (rc.FRAME_GRAPH_TIMERS) std.debug.print("{d:.3} us: OutputLoadSys\n", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start1)) / 1_000.0});

        const start35 = std.time.nanoTimestamp();
        try DependencySys.build(&self.dependency, &self.passLoad, &self.outputLoad, renderRegistry);
        if (rc.FRAME_GRAPH_TIMERS) std.debug.print("{d:.3} us: DependencySys\n", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start35)) / 1_000.0});

        const start4 = std.time.nanoTimestamp();
        try GraphSys2.build(&self.graph, &self.passLoad, &self.outputLoad, &self.dependency, renderRegistry);
        if (rc.FRAME_GRAPH_TIMERS) std.debug.print("{d:.3} us: GraphSys2\n", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start4)) / 1_000.0});

        const start2 = std.time.nanoTimestamp();
        try CompositeSys.build(&self.composite, &self.passLoad, &self.outputLoad, &self.graph, renderRegistry, viewportData, windowData);
        if (rc.FRAME_GRAPH_TIMERS) std.debug.print("{d:.3} us: CompositeSys\n", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start2)) / 1_000.0});

        const start3 = std.time.nanoTimestamp();
        try ResourceSys2.build(&self.resource, &self.composite, &self.dependency, renderRegistry);
        if (rc.FRAME_GRAPH_TIMERS) std.debug.print("{d:.3} us: ResourceSys2\n", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start3)) / 1_000.0});

        const start5 = std.time.nanoTimestamp();
        try OptimizerSys2.build(&self.optimizer, &self.passLoad, &self.graph, &self.dependency, &self.resource, renderRegistry);
        if (rc.FRAME_GRAPH_TIMERS) std.debug.print("{d:.3} us: OptimizerSys2\n", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start5)) / 1_000.0});

        const start6 = std.time.nanoTimestamp();
        try LifetimeSys2.build(&self.lifetime, &self.dependency, &self.resource, &self.optimizer, renderRegistry);
        if (rc.FRAME_GRAPH_TIMERS) std.debug.print("{d:.3} us: LifetimeSys2\n", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start6)) / 1_000.0});

        const start7 = std.time.nanoTimestamp();
        try ShareSys2.build(&self.share, &self.resource, &self.optimizer, &self.lifetime, renderRegistry);
        if (rc.FRAME_GRAPH_TIMERS) std.debug.print("{d:.3} us: ShareSys2\n", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start7)) / 1_000.0});

        const start8 = std.time.nanoTimestamp();
        try SorterSys2.build(&self.sorter, &self.composite, &self.optimizer, renderRegistry);
        if (rc.FRAME_GRAPH_TIMERS) std.debug.print("{d:.3} us: SorterSys2\n", .{@as(f64, @floatFromInt(std.time.nanoTimestamp() - start8)) / 1_000.0});
    }
};
