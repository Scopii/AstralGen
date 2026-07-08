const RenderRegistryData = @import("../../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const GraphMemoryNode = @import("../../renderGraph/components.zig").GraphMemoryNode;
const GraphLifetime = @import("../../renderGraph/components.zig").GraphLifetime;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const getResTyp = @import("../../renderGraph/components.zig").getResTyp;

const AccessData = @import("../1.5_Access/AccessData.zig").AccessData;
const ResourceData = @import("../2_Resource/ResourceData.zig").ResourceData;
const GraphData = @import("../4_Graph/GraphData.zig").GraphData;
const OptimizerData = @import("../4.5_Optimizer/OptimizerData.zig").OptimizerData;

// Step 4.5

pub const OptimizerSys = struct {
    pub fn build(optimizerData: *OptimizerData, graphData: *const GraphData, accessData: *const AccessData, resourceData: *const ResourceData, registry: *const RenderRegistryData) !void {
        optimizerData.optimizedGraph.clear();

        // Skip Optimizer Stage
        if (rc.FRAME_GRAPH_SKIP_OPTIMIZE == true) {
            for (graphData.graph.getConstItems()) |graphNode| {
                optimizerData.optimizedGraph.upsert(graphNode.passId, GraphMemoryNode{ .level = graphNode.level, .pass = graphNode.passId, .memWeight = 0 });
            }
            return;
        }
        // If not skipped:
        optimizerData.graphLifetimes.clear();
        optimizerData.graphMemNodes.clear();

        for (accessData.accesses.constSlice()) |access| {
            const graphLevel = graphData.graph.getByKey(access.pass).level;
            // Input
            const input = access.input;
            if (resourceData.memSizes.isKeyUsed(input) == true) { // Only Transient

                if (optimizerData.graphLifetimes.isKeyUsed(input) == false) {
                    optimizerData.graphLifetimes.upsert(input, GraphLifetime{ .firstLevel = graphLevel, .lastLevel = graphLevel });
                } else {
                    var graphLifetime = optimizerData.graphLifetimes.getPtrByKey(input);
                    if (graphLevel < graphLifetime.firstLevel) graphLifetime.firstLevel = graphLevel;
                    if (graphLevel > graphLifetime.lastLevel) graphLifetime.lastLevel = graphLevel;
                }
            }
            // Output
            const output = access.output orelse continue;
            if (resourceData.memSizes.isKeyUsed(output) == true) { // Only Transient

                if (optimizerData.graphLifetimes.isKeyUsed(output) == false) {
                    optimizerData.graphLifetimes.upsert(output, GraphLifetime{ .firstLevel = graphLevel, .lastLevel = graphLevel });
                } else {
                    var graphLifetime = optimizerData.graphLifetimes.getPtrByKey(output);
                    if (graphLevel < graphLifetime.firstLevel) graphLifetime.firstLevel = graphLevel;
                    if (graphLevel > graphLifetime.lastLevel) graphLifetime.lastLevel = graphLevel;
                }
            }
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("4.5.GraphOptimizer: \n", .{});
            for (0..optimizerData.graphLifetimes.getLength()) |i| {
                const graphLifetime = optimizerData.graphLifetimes.getByIndex(@intCast(i));
                const resKey = optimizerData.graphLifetimes.getKeyByIndex(@intCast(i));
                const resTyp = getResTyp(resKey);
                const resName = try registry.getResourceName(resKey);
                std.debug.print("- {s} Graph Lifetime: (Level {} -> {}) {s} \n", .{ @tagName(resTyp), graphLifetime.firstLevel, graphLifetime.lastLevel, resName });
            }
            std.debug.print("\n", .{});
        }

        // Extend GraphNodes to GraphMemoryNodes
        for (graphData.graph.getConstItems()) |graphNode| {
            const accessRange = accessData.accessRanges.getByKey(graphNode.passId);

            var bornBytes: u64 = 0;
            var dyingBytes: u64 = 0;

            for (accessData.accesses.buffer[accessRange.first..accessRange.last]) |access| {

                // Check Input Buffer Bytes
                const input = access.input;
                if (resourceData.memSizes.isKeyUsed(input) == true) { // Only Transient were filled!
                    const graphLifetime = optimizerData.graphLifetimes.getByKey(input);
                    if (graphLifetime.firstLevel == graphNode.level and graphLifetime.lastLevel != graphNode.level) bornBytes += resourceData.memSizes.getByKey(input);
                    if (graphLifetime.lastLevel == graphNode.level and graphLifetime.firstLevel != graphNode.level) dyingBytes += resourceData.memSizes.getByKey(input);
                }

                // Check Output Buffer Bytes
                if (access.output) |outputKey| {
                    const output = outputKey;
                    if (resourceData.memSizes.isKeyUsed(output) == true) { // Only Transient were filled!
                        const graphLifetime = optimizerData.graphLifetimes.getByKey(output);
                        if (graphLifetime.firstLevel == graphNode.level and graphLifetime.lastLevel != graphNode.level) bornBytes += resourceData.memSizes.getByKey(output);
                        if (graphLifetime.lastLevel == graphNode.level and graphLifetime.firstLevel != graphNode.level) dyingBytes += resourceData.memSizes.getByKey(output);
                    }
                }
            }

            const castedBornBytes: i64 = @intCast(bornBytes);
            const castedDyingBytes: i64 = @intCast(dyingBytes);

            const graphMemNode = GraphMemoryNode{ .level = graphNode.level, .pass = graphNode.passId, .memWeight = castedBornBytes - castedDyingBytes };
            optimizerData.graphMemNodes.append(graphMemNode) catch std.debug.print("ERROR: 4.5.PassOptimizer: Append to graphMemNodes failed!", .{});
        }

        // Sort first by Level then by Memory Byte Weight
        optimizerData.graphMemNodes.selectionSort(greaterGraphMemNode);

        for (optimizerData.graphMemNodes.constSlice()) |graphMemNode| {
            optimizerData.optimizedGraph.upsert(graphMemNode.pass, graphMemNode);
        }

        // Debug Output 2
        if (rc.FRAME_GRAPH_DEBUG) {
            for (optimizerData.optimizedGraph.getConstItems(), 0..) |pass, i| {
                const passName = try registry.getPassName(pass.pass);
                std.debug.print("- Nr. {}: .( .level = {}, .pass = {s}, .memWeight = {} )\n", .{ i, pass.level, passName, pass.memWeight });
            }
            std.debug.print("\n", .{});
        }
    }
};

fn greaterGraphMemNode(graphMemNode1: anytype, graphMemNode2: anytype) bool {
    if (graphMemNode1.level == graphMemNode2.level) {
        if (graphMemNode1.memWeight > graphMemNode2.memWeight) return true else return false;
    }

    if (graphMemNode1.level > graphMemNode2.level) return true;
    return false;
}
