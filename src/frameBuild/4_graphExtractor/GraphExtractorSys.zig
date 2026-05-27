const rc = @import("../../.configs/renderConfig.zig");
const PassEnum = @import("../enums.zig").PassEnum;
const std = @import("std");

const DependancyExtractorData = @import("../3_dependancyExtractor/DependancyExtractorData.zig").DependancyExtractorData;
const PassExtractorData = @import("../1_passExtractor/PassExtractorData.zig").PassExtractorData;
const GraphExtractorData = @import("GraphExtractorData.zig").GraphExtractorData;

// Step 4

pub const GraphExtractorSys = struct {
    pub fn buildGraph(graphExtractor: *GraphExtractorData, dependancyExtractor: *const DependancyExtractorData, passExtractor: *const PassExtractorData) !void {
        graphExtractor.passDepCounters.clear();
        graphExtractor.orderedPasses.clear();

        // Fill Passes with Buffer Dependancy Count
        for (dependancyExtractor.bufDependancies.constSlice()) |bufDep| {
            const passKey = @intFromEnum(bufDep.successor);
            const curDepCount = if (graphExtractor.passDepCounters.isKeyUsed(passKey)) graphExtractor.passDepCounters.getByKey(passKey) else 0;
            graphExtractor.passDepCounters.upsert(@intFromEnum(bufDep.successor), curDepCount + 1);
        }

        // Fill Passes with Texture Dependancy Count
        for (dependancyExtractor.texDependancies.constSlice()) |texDep| {
            const passKey = @intFromEnum(texDep.successor);
            const curDepCount = if (graphExtractor.passDepCounters.isKeyUsed(passKey)) graphExtractor.passDepCounters.getByKey(passKey) else 0;
            graphExtractor.passDepCounters.upsert(@intFromEnum(texDep.successor), curDepCount + 1);
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("4.GraphExtractor: \n", .{});
            for (0..graphExtractor.passDepCounters.getLength()) |i| {
                const castedIndex: u32 = @intCast(i);
                const passDepCount = graphExtractor.passDepCounters.getByIndex(castedIndex);
                const passKey = graphExtractor.passDepCounters.getKeyByIndex(castedIndex);
                const passEnum: PassEnum = @enumFromInt(passKey);
                std.debug.print("- Pass {}: Dependancies {}\n", .{ passEnum, passDepCount });
            }
            std.debug.print("\n", .{});
        }

        graphExtractor.unorderedPasses.clear();

        // Load Unordered Passes
        for (passExtractor.renderNodes.constSlice()) |*renderNode| {
            switch (renderNode.*) {
                .compositeNode, .uiNode, .viewportBlit, .clearBuffer, .clearTexture, .barrierBakeClears => {},
                .passNode => |passNode| {
                    graphExtractor.unorderedPasses.upsert(@intFromEnum(passNode.pass.name), passNode.pass.name);
                },
            }
        }

        graphExtractor.readyPasses.clear();

        // Add all Passes that do not have Dependancys
        for (graphExtractor.unorderedPasses.getConstItems()) |passEnum| {
            const passKey = @intFromEnum(passEnum);

            // If Dependancy Counter is null add to ordered List
            if (graphExtractor.passDepCounters.isKeyUsed(passKey) == false) {
                graphExtractor.readyPasses.append(.{ .passEnum = passEnum, .level = 0 }) catch {};
            }
        }

        var curLevel: u16 = 0;

        while (graphExtractor.readyPasses.len > 0) { // orderExtractor.passDepCounters.getLength() != 0
            curLevel += 1;
            // Repeat to solve Graph

            for (graphExtractor.readyPasses.constSlice()) |readyPass| {
                // Decrement Dependancy Counters
                for (dependancyExtractor.bufDependancies.constSlice()) |bufDep| {
                    if (bufDep.predecessor == readyPass.passEnum) {
                        const successorCountPtr = graphExtractor.passDepCounters.getPtrByKey(@intFromEnum(bufDep.successor));
                        successorCountPtr.* -= 1;
                    }
                }

                for (dependancyExtractor.texDependancies.constSlice()) |texDep| {
                    if (texDep.predecessor == readyPass.passEnum) {
                        const successorCountPtr = graphExtractor.passDepCounters.getPtrByKey(@intFromEnum(texDep.successor));
                        successorCountPtr.* -= 1;
                    }
                }
            }

            // Transfer all Ready Passes to Ordered Map
            for (graphExtractor.readyPasses.constSlice()) |readyPass| {
                graphExtractor.orderedPasses.upsert(@intFromEnum(readyPass.passEnum), readyPass);
            }
            graphExtractor.readyPasses.clear();

            // Fill move passes with Count 0 to readyPasses for new Cycle
            for (graphExtractor.passDepCounters.getConstItems(), 0..) |passDepCounter, i| {
                const passEnum: PassEnum = @enumFromInt(graphExtractor.passDepCounters.getKeyByIndex(@intCast(i)));
                if (passDepCounter == 0) graphExtractor.readyPasses.append(.{ .passEnum = passEnum, .level = curLevel }) catch {};
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
            for (graphExtractor.unorderedPasses.getConstItems()) |passEnum| {
                const key = @intFromEnum(passEnum);
                if (graphExtractor.orderedPasses.isKeyUsed(key) == false) {
                    const remainingDeps = if (graphExtractor.passDepCounters.isKeyUsed(key)) graphExtractor.passDepCounters.getByKey(key) else 0;
                    std.debug.print("  stuck: {s} (still waiting on {} deps)\n", .{ @tagName(passEnum), remainingDeps });
                }
            }
            std.debug.print("  cycle Buffer edges:\n", .{});
            for (dependancyExtractor.bufDependancies.constSlice()) |dep| {
                const predStuck = !graphExtractor.orderedPasses.isKeyUsed(@intFromEnum(dep.predecessor));
                const succStuck = !graphExtractor.orderedPasses.isKeyUsed(@intFromEnum(dep.successor));
                if (predStuck and succStuck) {
                    std.debug.print("    {s} --[{s}]--> {s}\n", .{ @tagName(dep.predecessor), @tagName(dep.bufEnum), @tagName(dep.successor) });
                }
            }
            std.debug.print("  cycle Texture edges:\n", .{});
            for (dependancyExtractor.texDependancies.constSlice()) |dep| {
                const predStuck = !graphExtractor.orderedPasses.isKeyUsed(@intFromEnum(dep.predecessor));
                const succStuck = !graphExtractor.orderedPasses.isKeyUsed(@intFromEnum(dep.successor));
                if (predStuck and succStuck) {
                    std.debug.print("    {s} --[{s}]--> {s}\n", .{ @tagName(dep.predecessor), @tagName(dep.texEnum), @tagName(dep.successor) });
                }
            }
            return error.GraphHasCycle;
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            for (graphExtractor.orderedPasses.getConstItems(), 0..) |pass, i| {
                std.debug.print("- Nr. {}: {}\n", .{ i, pass });
            }
            std.debug.print("\n", .{});
        }
    }
};
