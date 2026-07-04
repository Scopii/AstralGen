const GraphNode = @import("../components.zig").GraphNode;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const PassData = @import("../1_Pass/PassData.zig").PassData;
const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const DependancyData = @import("../3_Dependancy/DependancyData.zig").DependancyData;
const GraphData = @import("GraphData.zig").GraphData;

// Step 4

pub const GraphSys = struct {
    pub fn build(graphData: *GraphData, dependancyData: *const DependancyData, passData: *const PassData, registryData: *const RegistryData) !void {
        graphData.passDepCounters.clear();
        graphData.graph.clear();
        graphData.readyPasses.clear();

        // Fill Passes with Buffer Dependancy Count
        for (dependancyData.deps.constSlice()) |dep| {
            const curDepCount = if (graphData.passDepCounters.isKeyUsed(dep.successor)) graphData.passDepCounters.getByKey(dep.successor) else 0;
            graphData.passDepCounters.upsert(dep.successor, curDepCount + 1);
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("4.GraphExtractor: \n", .{});
            for (0..graphData.passDepCounters.getLength()) |i| {
                const passDepCount = graphData.passDepCounters.getByIndex(@intCast(i));
                const passId = graphData.passDepCounters.getKeyByIndex(@intCast(i));
                const passName = try registryData.getPassName(passId);
                std.debug.print("- Pass {s}: Dependancies {}\n", .{ passName, passDepCount });
            }
            std.debug.print("\n", .{});
        }

        // Add all Passes that do not have Dependancys
        for (passData.activePasses.getConstItems()) |pass| {
            if (graphData.passDepCounters.isKeyUsed(pass) == false) {
                graphData.readyPasses.appendAssumeCapacity(.{ .passId = pass, .level = 0 });
            }
        }

        // Single Queue Topological Sort
        var readIndex: u32 = 0;

        while (readIndex < graphData.readyPasses.len) {
            // Read current pass and advance index
            const pass = graphData.readyPasses.buffer[readIndex];
            readIndex += 1;
            // Place into ordered passes
            graphData.graph.upsert(pass.passId, pass);
            // Calc level for any children
            const nextLevel = pass.level + 1;

            // Decrement Buffer Dependencies
            for (dependancyData.deps.constSlice()) |bufDep| {
                if (bufDep.predecessor == pass.passId) {
                    const ptr = graphData.passDepCounters.getPtrByKey(bufDep.successor);
                    ptr.* -= 1;
                    // Queue to END of current list if its 0
                    if (ptr.* == 0) graphData.readyPasses.appendAssumeCapacity(GraphNode{ .passId = bufDep.successor, .level = nextLevel });
                }
            }
        }

        // Graph Validation Check
        const orderedCount = graphData.graph.getLength();
        const totalCount = passData.activePasses.getLength();

        if (orderedCount != totalCount) {
            std.debug.print("ERROR: 4.0.GraphExtractor: {} of {} passes scheduled! Graph has a cycle\n", .{ orderedCount, totalCount });
            // Passes in unorderedPasses but not in orderedPasses
            for (passData.activePasses.getConstItems()) |passId| {
                if (graphData.graph.isKeyUsed(passId) == false) {
                    const openDeps = if (graphData.passDepCounters.isKeyUsed(passId)) graphData.passDepCounters.getByKey(passId) else 0;
                    const passString = try registryData.getPassName(passId);
                    std.debug.print("  stuck: {s} (still waiting on {} deps)\n", .{ passString, openDeps });
                }
            }
            for (dependancyData.deps.constSlice()) |dep| {
                const predStuck = !graphData.graph.isKeyUsed(dep.predecessor);
                const succStuck = !graphData.graph.isKeyUsed(dep.successor);

                std.debug.print("  cycle {s} edges:\n", .{@tagName(dep.resource)});
                if (predStuck and succStuck) {
                    const resName = switch (dep.resource) {
                        .bufPassId => |id| try registryData.getBufferName(id),
                        .texPassId => |id| try registryData.getTextureName(id),
                    };
                    const predName = try registryData.getPassName(dep.predecessor);
                    const succName = try registryData.getPassName(dep.successor);
                    std.debug.print("    {s} --[{s}]--> {s}\n", .{ predName, resName, succName });
                }
            }
            return error.GraphHasCycle;
        }

        // Debug
        if (rc.FRAME_GRAPH_DEBUG) {
            for (graphData.graph.getConstItems(), 0..) |pass, i| {
                const passName = try registryData.getPassName(pass.passId);
                std.debug.print("- Nr. {}: .( .level = {}, .pass = {s})\n", .{ i, pass.level, passName });
            }
            std.debug.print("\n", .{});
        }
    }
};
