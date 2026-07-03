const GraphMemoryNode = @import("../../frameBuild/components.zig").GraphMemoryNode;
const GraphLifetime = @import("../../frameBuild/components.zig").GraphLifetime;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const AccessData = @import("../1.5_Access/AccessData.zig").AccessData;
const ResourceData = @import("../2_Resource/ResourceData.zig").ResourceData;
const GraphData = @import("../4_Graph/GraphData.zig").GraphData;
const OptimizerData = @import("../4.5_Optimizer/OptimizerData.zig").OptimizerData;

// Step 4.5

pub const OptimizerSys = struct {
    pub fn assignResourceLevels(optimizerData: *OptimizerData, graphData: *const GraphData, accessData: *const AccessData, resourceData: *const ResourceData, registryData: *const RegistryData) !void {
        // Skip Optimizer Stage
        if (rc.FRAME_GRAPH_SKIP_OPTIMIZE == true) {
            for (graphData.graph.getConstItems()) |graphNode| {
                optimizerData.optimizedGraph.upsert(graphNode.passId, .{ .level = graphNode.level, .pass = graphNode.passId, .memWeight = 0 });
            }
            return;
        }

        // If not skipped:
        optimizerData.bufGraphLifetimes.clear();
        optimizerData.texGraphLifetimes.clear();

        optimizerData.graphMemNodes.clear();
        optimizerData.optimizedGraph.clear();

        // Assign Buffers Lifetime
        for (accessData.bufAccesses.constSlice()) |bufAccess| {
            const graphLevel = graphData.graph.getByKey(bufAccess.pass).level;
            // Input
            const bufInput = bufAccess.input;
            if (resourceData.bufMemSizes.isKeyUsed(bufInput) == true) { // Only Transient

                if (optimizerData.bufGraphLifetimes.isKeyUsed(bufInput) == false) {
                    optimizerData.bufGraphLifetimes.upsert(bufInput, GraphLifetime{ .firstLevel = graphLevel, .lastLevel = graphLevel });
                } else {
                    var graphLifetime = optimizerData.bufGraphLifetimes.getPtrByKey(bufInput);
                    if (graphLevel < graphLifetime.firstLevel) graphLifetime.firstLevel = graphLevel;
                    if (graphLevel > graphLifetime.lastLevel) graphLifetime.lastLevel = graphLevel;
                }
            }
            // Output
            const bufOutput = bufAccess.output orelse continue;
            if (resourceData.bufMemSizes.isKeyUsed(bufOutput) == true) { // Only Transient

                if (optimizerData.bufGraphLifetimes.isKeyUsed(bufOutput) == false) {
                    optimizerData.bufGraphLifetimes.upsert(bufOutput, GraphLifetime{ .firstLevel = graphLevel, .lastLevel = graphLevel });
                } else {
                    var graphLifetime = optimizerData.bufGraphLifetimes.getPtrByKey(bufOutput);
                    if (graphLevel < graphLifetime.firstLevel) graphLifetime.firstLevel = graphLevel;
                    if (graphLevel > graphLifetime.lastLevel) graphLifetime.lastLevel = graphLevel;
                }
            }
        }

        // Assign texture Lifetime
        for (accessData.texAccesses.constSlice()) |texAccess| {
            const graphLevel = graphData.graph.getByKey(texAccess.pass).level;
            // Input
            const texInput = texAccess.input;
            if (resourceData.texMemSizeS.isKeyUsed(texInput) == true) { // Only Transient

                if (optimizerData.texGraphLifetimes.isKeyUsed(texInput) == false) {
                    optimizerData.texGraphLifetimes.upsert(texInput, GraphLifetime{ .firstLevel = graphLevel, .lastLevel = graphLevel });
                } else {
                    var graphLifetime = optimizerData.texGraphLifetimes.getPtrByKey(texInput);
                    if (graphLevel < graphLifetime.firstLevel) graphLifetime.firstLevel = graphLevel;
                    if (graphLevel > graphLifetime.lastLevel) graphLifetime.lastLevel = graphLevel;
                }
            }
            // Output
            const texOutput = texAccess.output orelse continue;
            if (resourceData.texMemSizeS.isKeyUsed(texOutput) == true) { // Only Transient

                if (optimizerData.texGraphLifetimes.isKeyUsed(texOutput) == false) {
                    optimizerData.texGraphLifetimes.upsert(texOutput, GraphLifetime{ .firstLevel = graphLevel, .lastLevel = graphLevel });
                } else {
                    var graphLifetime = optimizerData.texGraphLifetimes.getPtrByKey(texOutput);
                    if (graphLevel < graphLifetime.firstLevel) graphLifetime.firstLevel = graphLevel;
                    if (graphLevel > graphLifetime.lastLevel) graphLifetime.lastLevel = graphLevel;
                }
            }
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("4.5.GraphOptimizer: \n", .{});
            // Buffer Debug
            for (0..optimizerData.bufGraphLifetimes.getLength()) |i| {
                const bufGraphLifetime = optimizerData.bufGraphLifetimes.getByIndex(@intCast(i));
                const bufPassId = optimizerData.bufGraphLifetimes.getKeyByIndex(@intCast(i));
                const bufName = try registryData.getBufferName(bufPassId);
                std.debug.print("- Buf Graph Lifetime: (Level {} -> {}) {s} \n", .{ bufGraphLifetime.firstLevel, bufGraphLifetime.lastLevel, bufName });
            }
            // Texture Debug
            for (0..optimizerData.texGraphLifetimes.getLength()) |i| {
                const texGraphLifetime = optimizerData.texGraphLifetimes.getByIndex(@intCast(i));
                const texPassId = optimizerData.texGraphLifetimes.getKeyByIndex(@intCast(i));
                const texName = try registryData.getTextureName(texPassId);
                std.debug.print("- Tex Graph Lifetime: (Level {} -> {}) {s}\n", .{ texGraphLifetime.firstLevel, texGraphLifetime.lastLevel, texName });
            }
            std.debug.print("\n", .{});
        }

        // Extend GraphNodes to GraphMemoryNodes
        for (graphData.graph.getConstItems()) |graphNode| {
            const accessRange = accessData.passAccessRanges.getByKey(graphNode.passId);

            var bornBytes: u64 = 0;
            var dyingBytes: u64 = 0;

            // Buffers
            for (accessRange.firstBuf..accessRange.lastBuf) |bufIndex| {
                const bufAccess = accessData.bufAccesses.buffer[bufIndex];
                const bufInput = bufAccess.input;

                // Check Input Buffer Bytes
                if (resourceData.bufMemSizes.isKeyUsed(bufInput) == true) { // Only Transient were filled!
                    const graphLifetime = optimizerData.bufGraphLifetimes.getByKey(bufInput);
                    if (graphLifetime.firstLevel == graphNode.level and graphLifetime.lastLevel != graphNode.level) bornBytes += resourceData.bufMemSizes.getByKey(bufInput);
                    if (graphLifetime.lastLevel == graphNode.level and graphLifetime.firstLevel != graphNode.level) dyingBytes += resourceData.bufMemSizes.getByKey(bufInput);
                }

                // Check Output Buffer Bytes
                if (bufAccess.output) |bufOutput| {
                    if (resourceData.bufMemSizes.isKeyUsed(bufOutput) == true) { // Only Transient were filled!
                        const graphLifetime = optimizerData.bufGraphLifetimes.getByKey(bufOutput);
                        if (graphLifetime.firstLevel == graphNode.level and graphLifetime.lastLevel != graphNode.level) bornBytes += resourceData.bufMemSizes.getByKey(bufOutput);
                        if (graphLifetime.lastLevel == graphNode.level and graphLifetime.firstLevel != graphNode.level) dyingBytes += resourceData.bufMemSizes.getByKey(bufOutput);
                    }
                }
            }

            // Textures
            for (accessRange.firstTex..accessRange.lastTex) |texIndex| {
                const texAccess = accessData.texAccesses.buffer[texIndex];
                const texInput = texAccess.input;

                // Check Input Texture Bytes
                if (resourceData.texMemSizeS.isKeyUsed(texInput) == true) { // Only Transient were filled!
                    const graphLifetime = optimizerData.texGraphLifetimes.getByKey(texInput);
                    if (graphLifetime.firstLevel == graphNode.level and graphLifetime.lastLevel != graphNode.level) bornBytes += resourceData.texMemSizeS.getByKey(texInput);
                    if (graphLifetime.lastLevel == graphNode.level and graphLifetime.firstLevel != graphNode.level) dyingBytes += resourceData.texMemSizeS.getByKey(texInput);
                }

                // Check Output Buffer Bytes
                if (texAccess.output) |texOutput| {
                    if (resourceData.texMemSizeS.isKeyUsed(texOutput) == true) { // Only Transient were filled!
                        const graphLifetime = optimizerData.texGraphLifetimes.getByKey(texOutput);
                        if (graphLifetime.firstLevel == graphNode.level and graphLifetime.lastLevel != graphNode.level) bornBytes += resourceData.texMemSizeS.getByKey(texOutput);
                        if (graphLifetime.lastLevel == graphNode.level and graphLifetime.firstLevel != graphNode.level) dyingBytes += resourceData.texMemSizeS.getByKey(texOutput);
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
                const passName = try registryData.getPassName(pass.pass);
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
