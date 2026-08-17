const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const SimpleIdMap = @import("../.structures/SimpleIdMap.zig").SimpleIdMap;
const LinkedIdMap = @import("../.structures/LinkedIdMap.zig").LinkedIdMap;
const GraphNode = @import("../renderGraph/components.zig").GraphNode;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const OutputLoadData = @import("2_OutputLoad.zig").OutputLoadData;
const ResourceData = @import("4_Resource.zig").ResourceData;
const PassId = @import("../.configs/idConfig.zig").PassId;
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

pub const GraphData = struct {
    passDepCounters: LinkedIdMap(u16, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
    readyPasses: FixedList(GraphNode, rc.PASS_MAX) = .{},
    graph: SimpleIdMap(GraphNode, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
};

pub const GraphSys = struct {
    pub fn build(self: *GraphData, outputLoad: *const OutputLoadData, resource: *const ResourceData, registry: *const RenderRegistryData) !void {
        self.passDepCounters.clear();
        self.graph.clear();
        self.readyPasses.clear();

        // Fill Passes with Buffer Dependancy Count
        for (resource.dependencies.constSlice()) |dep| {
            const curDepCount = if (self.passDepCounters.isKeyUsed(dep.successor)) self.passDepCounters.getByKey(dep.successor) else 0;
            self.passDepCounters.upsert(dep.successor, curDepCount + 1);
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.GraphExtractor: \n", .{});
            for (0..self.passDepCounters.getLength()) |i| {
                const passDepCount = self.passDepCounters.getByIndex(@intCast(i));
                const passId = self.passDepCounters.getKeyByIndex(@intCast(i));
                const passName = try registry.getPassName(passId);
                std.debug.print("- Pass {s}: Dependancies {}\n", .{ passName, passDepCount });
            }
            std.debug.print("\n", .{});
        }

        // Add all Passes that do not have Dependancys
        for (outputLoad.activePasses.getConstItems()) |pass| {
            if (self.passDepCounters.isKeyUsed(pass) == false) {
                self.readyPasses.appendAssumeCapacity(.{ .passId = pass, .level = 0 });
            }
        }

        // Single Queue Topological Sort
        var readIndex: u32 = 0;

        while (readIndex < self.readyPasses.len) {
            // Read current pass and advance index
            const pass = self.readyPasses.buffer[readIndex];
            readIndex += 1;
            // Place into ordered passes
            self.graph.upsert(pass.passId, pass);
            // Calc level for any children
            const nextLevel = pass.level + 1;

            // Decrement Buffer Dependencies
            for (resource.dependencies.constSlice()) |dependency| {
                if (dependency.predecessor == pass.passId) {
                    const ptr = self.passDepCounters.getPtrByKey(dependency.successor);
                    ptr.* -= 1;
                    // Queue to END of current list if its 0
                    if (ptr.* == 0) self.readyPasses.appendAssumeCapacity(GraphNode{ .passId = dependency.successor, .level = nextLevel });
                }
            }
        }

        // Graph Validation Check
        const orderedCount = self.graph.getLength();
        const totalCount = outputLoad.activePasses.getLength();

        if (orderedCount != totalCount) {
            std.debug.print("ERROR: 4.0.GraphExtractor: {} of {} passes scheduled! Graph has a cycle\n", .{ orderedCount, totalCount });
            // Passes in unorderedPasses but not in orderedPasses
            for (outputLoad.activePasses.getConstItems()) |passId| {
                if (self.graph.isKeyUsed(passId) == false) {
                    const openDeps = if (self.passDepCounters.isKeyUsed(passId)) self.passDepCounters.getByKey(passId) else 0;
                    const passString = try registry.getPassName(passId);
                    std.debug.print("  stuck: {s} (still waiting on {} deps)\n", .{ passString, openDeps });
                }
            }
            for (resource.dependencies.constSlice()) |dep| {
                const predStuck = !self.graph.isKeyUsed(dep.predecessor);
                const succStuck = !self.graph.isKeyUsed(dep.successor);

                if (predStuck and succStuck) {
                    const predName = try registry.getPassName(dep.predecessor);
                    const succName = try registry.getPassName(dep.successor);
                    std.debug.print("    {s} -- --> {s}\n", .{ predName, succName });
                }
            }
            return error.GraphHasCycle;
        }

        // Debug
        if (rc.FRAME_GRAPH_DEBUG) {
            for (self.graph.getConstItems(), 0..) |pass, i| {
                const passName = try registry.getPassName(pass.passId);
                std.debug.print("- Nr. {}: .( .level = {}, .pass = {s})\n", .{ i, pass.level, passName });
            }
            std.debug.print("\n", .{});
        }
    }
};
