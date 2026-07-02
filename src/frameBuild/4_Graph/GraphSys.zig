const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const DependancyData = @import("../3_Dependancy/DependancyData.zig").DependancyData;
const PassData = @import("../1_Pass/PassData.zig").PassData;
const GraphData = @import("GraphData.zig").GraphData;
const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;

// Step 4

pub const GraphSys = struct {
    pub fn buildGraph(graphData: *GraphData, dependancyData: *const DependancyData, passData: *const PassData, registryData: *const RegistryData) !void {
        graphData.passDepCounters.clear();
        graphData.orderedPasses.clear();

        // Fill Passes with Buffer Dependancy Count
        for (dependancyData.bufDeps.constSlice()) |bufDep| {
            const passKey = bufDep.successor.val();
            const curDepCount = if (graphData.passDepCounters.isKeyUsed(passKey)) graphData.passDepCounters.getByKey(passKey) else 0;
            graphData.passDepCounters.upsert(bufDep.successor.val(), curDepCount + 1);
        }

        // Fill Passes with Texture Dependancy Count
        for (dependancyData.texDeps.constSlice()) |texDep| {
            const passKey = texDep.successor.val();
            const curDepCount = if (graphData.passDepCounters.isKeyUsed(passKey)) graphData.passDepCounters.getByKey(passKey) else 0;
            graphData.passDepCounters.upsert(texDep.successor.val(), curDepCount + 1);
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("4.GraphExtractor: \n", .{});
            for (0..graphData.passDepCounters.getLength()) |i| {
                const passDepCount = graphData.passDepCounters.getByIndex(@intCast(i));
                const passKey = graphData.passDepCounters.getKeyByIndex(@intCast(i));
                const passString = try registryData.getPassName(.id(passKey));
                std.debug.print("- Pass {s}: Dependancies {}\n", .{ passString, passDepCount });
            }
            std.debug.print("\n", .{});
        }

        graphData.unorderedPasses.clear();

        // Load Unordered Passes
        for (passData.activePasses.getConstItems()) |passId| {
            graphData.unorderedPasses.upsert(passId.val(), passId);
        }

        graphData.readyPasses.clear();

        // Add all Passes that do not have Dependancys
        for (graphData.unorderedPasses.getConstItems()) |pass| {
            // If Dependancy Counter is null add to ordered List
            if (graphData.passDepCounters.isKeyUsed(pass.val()) == false) {
                graphData.readyPasses.append(.{ .pass = pass, .level = 0 }) catch {};
            }
        }

        var curLevel: u16 = 0;

        while (graphData.readyPasses.len > 0) { // orderExtractor.passDepCounters.getLength() != 0
            curLevel += 1;
            // Repeat to solve Graph

            for (graphData.readyPasses.constSlice()) |readyPass| {
                // Decrement Dependancy Counters
                for (dependancyData.bufDeps.constSlice()) |bufDep| {
                    if (bufDep.predecessor.val() == readyPass.pass.val()) {
                        const successorCountPtr = graphData.passDepCounters.getPtrByKey(bufDep.successor.val());
                        successorCountPtr.* -= 1;
                    }
                }

                for (dependancyData.texDeps.constSlice()) |texDep| {
                    if (texDep.predecessor.val() == readyPass.pass.val()) {
                        const successorCountPtr = graphData.passDepCounters.getPtrByKey(texDep.successor.val());
                        successorCountPtr.* -= 1;
                    }
                }
            }

            // Transfer all Ready Passes to Ordered Map
            for (graphData.readyPasses.constSlice()) |readyPass| {
                graphData.orderedPasses.upsert(readyPass.pass.val(), readyPass);
            }
            graphData.readyPasses.clear();

            // Fill move passes with Count 0 to readyPasses for new Cycle
            for (graphData.passDepCounters.getConstItems(), 0..) |passDepCounter, i| {
                const pass = graphData.passDepCounters.getKeyByIndex(@intCast(i));
                if (passDepCounter == 0) graphData.readyPasses.append(.{ .pass = .id(pass), .level = curLevel }) catch {};
            }

            // Cleanup Counters
            const counterLength = graphData.passDepCounters.getLength();
            for (0..counterLength) |i| {
                const iterator: u32 = @intCast(i);
                const index = counterLength - iterator - 1;
                if (graphData.passDepCounters.getByIndex(index) == 0) graphData.passDepCounters.removeIndex(index);
            }
        }

        // Check if Graph is Valid
        const orderedCount = graphData.orderedPasses.getLength();
        const totalCount = graphData.unorderedPasses.getLength();

        if (orderedCount != totalCount) {
            std.debug.print("ERROR: 4.0.GraphExtractor: {} of {} passes scheduled! Graph has a cycle\n", .{ orderedCount, totalCount });

            // Passes in unorderedPasses but not in orderedPasses
            for (graphData.unorderedPasses.getConstItems()) |passId| {
                const passString = try registryData.getPassName(passId);

                if (graphData.orderedPasses.isKeyUsed(passId.val()) == false) {
                    const remainingDeps = if (graphData.passDepCounters.isKeyUsed(passId.val())) graphData.passDepCounters.getByKey(passId.val()) else 0;
                    std.debug.print("  stuck: {s} (still waiting on {} deps)\n", .{ passString, remainingDeps });
                }
            }
            std.debug.print("  cycle Buffer edges:\n", .{});
            for (dependancyData.bufDeps.constSlice()) |dep| {
                const predStuck = !graphData.orderedPasses.isKeyUsed(dep.predecessor.val());
                const succStuck = !graphData.orderedPasses.isKeyUsed(dep.successor.val());
                if (predStuck and succStuck) {
                    const predString = try registryData.getPassName(dep.predecessor);
                    const succString = try registryData.getPassName(dep.successor);
                    const bufName = try registryData.getBufferName(dep.buf);
                    std.debug.print("    {s} --[{s}]--> {s}\n", .{ predString, bufName, succString });
                }
            }
            std.debug.print("  cycle Texture edges:\n", .{});
            for (dependancyData.texDeps.constSlice()) |dep| {
                const predStuck = !graphData.orderedPasses.isKeyUsed(dep.predecessor.val());
                const succStuck = !graphData.orderedPasses.isKeyUsed(dep.successor.val());
                if (predStuck and succStuck) {
                    const predString = try registryData.getPassName(dep.predecessor);
                    const succString = try registryData.getPassName(dep.successor);
                    const texName = try registryData.getTextureName(dep.tex);
                    std.debug.print("    {s} --[{s}]--> {s}\n", .{ predString, texName, succString });
                }
            }
            return error.GraphHasCycle;
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            for (graphData.orderedPasses.getConstItems(), 0..) |pass, i| {
                const passName = try registryData.getPassName(pass.pass);
                std.debug.print("- Nr. {}: .( .level = {}, .pass = {s})\n", .{ i, pass.level, passName });
            }
            std.debug.print("\n", .{});
        }
    }
};
