const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const DependancyExtractorData = @import("../3_dependancyExtractor/DependancyExtractorData.zig").DependancyExtractorData;
const PassExtractorData = @import("../1_passExtractor/PassExtractorData.zig").PassExtractorData;
const GraphExtractorData = @import("GraphExtractorData.zig").GraphExtractorData;
const ResourceRegistryData = @import("../0_resourceRegistry/ResourceRegistryData.zig").ResourceRegistryData;

// Step 4

pub const GraphExtractorSys = struct {
    pub fn buildGraph(
        graphExtractor: *GraphExtractorData,
        dependancyExtractor: *const DependancyExtractorData,
        passExtractor: *const PassExtractorData,
        resourceRegistry: *const ResourceRegistryData,
    ) !void {
        graphExtractor.passDepCounters.clear();
        graphExtractor.orderedPasses.clear();

        // Fill Passes with Buffer Dependancy Count
        for (dependancyExtractor.bufDependancies.constSlice()) |bufDep| {
            const passKey = bufDep.successor.val();
            const curDepCount = if (graphExtractor.passDepCounters.isKeyUsed(passKey)) graphExtractor.passDepCounters.getByKey(passKey) else 0;
            graphExtractor.passDepCounters.upsert(bufDep.successor.val(), curDepCount + 1);
        }

        // Fill Passes with Texture Dependancy Count
        for (dependancyExtractor.texDependancies.constSlice()) |texDep| {
            const passKey = texDep.successor.val();
            const curDepCount = if (graphExtractor.passDepCounters.isKeyUsed(passKey)) graphExtractor.passDepCounters.getByKey(passKey) else 0;
            graphExtractor.passDepCounters.upsert(texDep.successor.val(), curDepCount + 1);
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("4.GraphExtractor: \n", .{});
            for (0..graphExtractor.passDepCounters.getLength()) |i| {
                const passDepCount = graphExtractor.passDepCounters.getByIndex(@intCast(i));
                const passKey = graphExtractor.passDepCounters.getKeyByIndex(@intCast(i));
                const passString = passExtractor.passStrings.getByKey(passKey);
                std.debug.print("- Pass {s}: Dependancies {}\n", .{ passString, passDepCount });
            }
            std.debug.print("\n", .{});
        }

        graphExtractor.unorderedPasses.clear();

        // Load Unordered Passes
        for (0..passExtractor.renderNodes.getLength()) |index| {
            const renderNode = passExtractor.renderNodes.getByIndex(@intCast(index));

            switch (renderNode) {
                .compositeNode, .uiNode, .viewportBlit, .clearBuffer, .clearTexture, .barrierBakeClears => {},
                .passNode => |_| {
                    const key = passExtractor.renderNodes.getKeyByIndex(@intCast(index));
                    graphExtractor.unorderedPasses.upsert(key, .id(key));
                },
            }
        }

        graphExtractor.readyPasses.clear();

        // Add all Passes that do not have Dependancys
        for (graphExtractor.unorderedPasses.getConstItems()) |pass| {
            // If Dependancy Counter is null add to ordered List
            if (graphExtractor.passDepCounters.isKeyUsed(pass.val()) == false) {
                graphExtractor.readyPasses.append(.{ .pass = pass, .level = 0 }) catch {};
            }
        }

        var curLevel: u16 = 0;

        while (graphExtractor.readyPasses.len > 0) { // orderExtractor.passDepCounters.getLength() != 0
            curLevel += 1;
            // Repeat to solve Graph

            for (graphExtractor.readyPasses.constSlice()) |readyPass| {
                // Decrement Dependancy Counters
                for (dependancyExtractor.bufDependancies.constSlice()) |bufDep| {
                    if (bufDep.predecessor.val() == readyPass.pass.val()) {
                        const successorCountPtr = graphExtractor.passDepCounters.getPtrByKey(bufDep.successor.val());
                        successorCountPtr.* -= 1;
                    }
                }

                for (dependancyExtractor.texDependancies.constSlice()) |texDep| {
                    if (texDep.predecessor.val() == readyPass.pass.val()) {
                        const successorCountPtr = graphExtractor.passDepCounters.getPtrByKey(texDep.successor.val());
                        successorCountPtr.* -= 1;
                    }
                }
            }

            // Transfer all Ready Passes to Ordered Map
            for (graphExtractor.readyPasses.constSlice()) |readyPass| {
                graphExtractor.orderedPasses.upsert(readyPass.pass.val(), readyPass);
            }
            graphExtractor.readyPasses.clear();

            // Fill move passes with Count 0 to readyPasses for new Cycle
            for (graphExtractor.passDepCounters.getConstItems(), 0..) |passDepCounter, i| {
                const pass = graphExtractor.passDepCounters.getKeyByIndex(@intCast(i));
                if (passDepCounter == 0) graphExtractor.readyPasses.append(.{ .pass = .id(pass), .level = curLevel }) catch {};
            }

            // Cleanup Counters
            const counterLength = graphExtractor.passDepCounters.getLength();
            for (0..counterLength) |i| {
                const iterator: u32 = @intCast(i);
                const index = counterLength - iterator - 1;
                if (graphExtractor.passDepCounters.getByIndex(index) == 0) graphExtractor.passDepCounters.removeIndex(index);
            }
        }

        // Check if Graph is Valid
        const orderedCount = graphExtractor.orderedPasses.getLength();
        const totalCount = graphExtractor.unorderedPasses.getLength();

        if (orderedCount != totalCount) {
            std.debug.print("ERROR: 4.0.GraphExtractor: {} of {} passes scheduled! Graph has a cycle\n", .{ orderedCount, totalCount });

            // Passes in unorderedPasses but not in orderedPasses
            for (graphExtractor.unorderedPasses.getConstItems()) |passId| {
                const passString = passExtractor.passStrings.getByKey(passId.val());

                if (graphExtractor.orderedPasses.isKeyUsed(passId.val()) == false) {
                    const remainingDeps = if (graphExtractor.passDepCounters.isKeyUsed(passId.val())) graphExtractor.passDepCounters.getByKey(passId.val()) else 0;
                    std.debug.print("  stuck: {s} (still waiting on {} deps)\n", .{ passString, remainingDeps });
                }
            }
            std.debug.print("  cycle Buffer edges:\n", .{});
            for (dependancyExtractor.bufDependancies.constSlice()) |dep| {
                const predStuck = !graphExtractor.orderedPasses.isKeyUsed(dep.predecessor.val());
                const succStuck = !graphExtractor.orderedPasses.isKeyUsed(dep.successor.val());
                if (predStuck and succStuck) {
                    const predString = passExtractor.passStrings.getByKey(dep.predecessor.val());
                    const succString = passExtractor.passStrings.getByKey(dep.successor.val());
                    const bufName = try resourceRegistry.getBufferName(dep.buf);
                    std.debug.print("    {s} --[{s}]--> {s}\n", .{ predString, bufName, succString });
                }
            }
            std.debug.print("  cycle Texture edges:\n", .{});
            for (dependancyExtractor.texDependancies.constSlice()) |dep| {
                const predStuck = !graphExtractor.orderedPasses.isKeyUsed(dep.predecessor.val());
                const succStuck = !graphExtractor.orderedPasses.isKeyUsed(dep.successor.val());
                if (predStuck and succStuck) {
                    const predString = passExtractor.passStrings.getByKey(dep.predecessor.val());
                    const succString = passExtractor.passStrings.getByKey(dep.successor.val());
                    const texName = try resourceRegistry.getTextureName(dep.tex);
                    std.debug.print("    {s} --[{s}]--> {s}\n", .{ predString, texName, succString });
                }
            }
            return error.GraphHasCycle;
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            for (graphExtractor.orderedPasses.getConstItems(), 0..) |pass, i| {
                const passName = try resourceRegistry.getPassName(pass.pass);
                std.debug.print("- Nr. {}: .( .level = {}, .pass = {s})\n", .{ i, pass.level, passName });
            }
            std.debug.print("\n", .{});
        }
    }
};
