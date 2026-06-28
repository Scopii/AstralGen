const TexLevelLifetime = @import("../../frameBuild/components.zig").TexLevelLifetime;
const BufLevelLifetime = @import("../../frameBuild/components.zig").BufLevelLifetime;
const GraphMemoryNode = @import("../../frameBuild/components.zig").GraphMemoryNode;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const ResourceRegistryData = @import("../0_resourceRegistry/ResourceRegistryData.zig").ResourceRegistryData;
const ResourceExtractorData = @import("../2_resourceExtractor/ResourceExtractorData.zig").ResourceExtractorData;
const GraphExtractorData = @import("../4_graphExtractor/GraphExtractorData.zig").GraphExtractorData;
const GraphOptimizerData = @import("../4.5_graphOptimizer/GraphOptimizerData.zig").GraphOptimizerData;

// Step 4.5

pub const GraphOptimizerSys = struct {
    pub fn assignResourceLevels(
        graphOptimizer: *GraphOptimizerData,
        graphExtractor: *const GraphExtractorData,
        resourceExtractor: *const ResourceExtractorData,
        resourceRegistry: *const ResourceRegistryData,
    ) !void {
        graphOptimizer.bufLevelLifetimes.clear();
        graphOptimizer.texLevelLifetimes.clear();

        graphOptimizer.graphMemNodes.clear();
        graphOptimizer.optimizedGraph.clear();

        // Assign Buffers Lifetime
        for (resourceExtractor.bufAccesses.constSlice()) |bufAccess| {
            const bufInputKey = bufAccess.bufInput.val();
            if (resourceExtractor.bufMemSize.isKeyUsed(bufInputKey) == false) continue; // Only Transient

            const graphLevel = graphExtractor.orderedPasses.getByKey(bufAccess.pass.val()).level;

            if (graphOptimizer.bufLevelLifetimes.isKeyUsed(bufInputKey) == false) {
                const bufLevelLifetime = BufLevelLifetime{ .buf = bufAccess.bufInput, .firstLevel = graphLevel, .lastLevel = graphLevel };
                graphOptimizer.bufLevelLifetimes.upsert(bufInputKey, bufLevelLifetime);
            } else {
                var bufLevelLifetime = graphOptimizer.bufLevelLifetimes.getPtrByKey(bufInputKey);
                if (graphLevel < bufLevelLifetime.firstLevel) bufLevelLifetime.firstLevel = graphLevel;
                if (graphLevel > bufLevelLifetime.lastLevel) bufLevelLifetime.lastLevel = graphLevel;
            }
        }

        for (resourceExtractor.bufAccesses.constSlice()) |bufAccess| {
            const bufOutput = bufAccess.bufOutput orelse continue;
            const bufOutputKey = bufOutput.val();
            if (resourceExtractor.bufMemSize.isKeyUsed(bufOutputKey) == false) continue; // Only Transient

            const graphLevel = graphExtractor.orderedPasses.getByKey(bufAccess.pass.val()).level;

            if (graphOptimizer.bufLevelLifetimes.isKeyUsed(bufOutputKey) == false) {
                const bufLevelLifetime = BufLevelLifetime{ .buf = bufOutput, .firstLevel = graphLevel, .lastLevel = graphLevel };
                graphOptimizer.bufLevelLifetimes.upsert(bufOutputKey, bufLevelLifetime);
            } else {
                var bufLevelLifetime = graphOptimizer.bufLevelLifetimes.getPtrByKey(bufOutputKey);
                if (graphLevel < bufLevelLifetime.firstLevel) bufLevelLifetime.firstLevel = graphLevel;
                if (graphLevel > bufLevelLifetime.lastLevel) bufLevelLifetime.lastLevel = graphLevel;
            }
        }

        // Assign texture Lifetime
        for (resourceExtractor.texAccesses.constSlice()) |texAccess| {
            const texInputKey = texAccess.texInput.val();
            if (resourceExtractor.texMemSize.isKeyUsed(texInputKey) == false) continue; // Only Transient

            const graphLevel = graphExtractor.orderedPasses.getByKey(texAccess.pass.val()).level;

            if (graphOptimizer.texLevelLifetimes.isKeyUsed(texInputKey) == false) {
                const texLevelLifetime = TexLevelLifetime{ .tex = texAccess.texInput, .firstLevel = graphLevel, .lastLevel = graphLevel };
                graphOptimizer.texLevelLifetimes.upsert(texInputKey, texLevelLifetime);
            } else {
                var texLevelLifetime = graphOptimizer.texLevelLifetimes.getPtrByKey(texInputKey);
                if (graphLevel < texLevelLifetime.firstLevel) texLevelLifetime.firstLevel = graphLevel;
                if (graphLevel > texLevelLifetime.lastLevel) texLevelLifetime.lastLevel = graphLevel;
            }
        }

        for (resourceExtractor.texAccesses.constSlice()) |texAccess| {
            const texOutput = texAccess.texOutput orelse continue;
            const texOutputKey = texOutput.val();
            if (resourceExtractor.texMemSize.isKeyUsed(texOutputKey) == false) continue; // Only Transient

            const graphLevel = graphExtractor.orderedPasses.getByKey(texAccess.pass.val()).level;

            if (graphOptimizer.texLevelLifetimes.isKeyUsed(texOutputKey) == false) {
                const texLevelLifetime = TexLevelLifetime{ .tex = texOutput, .firstLevel = graphLevel, .lastLevel = graphLevel };
                graphOptimizer.texLevelLifetimes.upsert(texOutputKey, texLevelLifetime);
            } else {
                var texLevelLifetime = graphOptimizer.texLevelLifetimes.getPtrByKey(texOutputKey);
                if (graphLevel < texLevelLifetime.firstLevel) texLevelLifetime.firstLevel = graphLevel;
                if (graphLevel > texLevelLifetime.lastLevel) texLevelLifetime.lastLevel = graphLevel;
            }
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("4.5.GraphOptimizer: \n", .{});
            
            // Buffer Debug
            for (0..graphOptimizer.bufLevelLifetimes.getLength()) |i| {
                const bufLevelLifetime = graphOptimizer.bufLevelLifetimes.getByIndex(@intCast(i));
                const bufName = try resourceRegistry.getBufferName(bufLevelLifetime.buf);
                std.debug.print("- Buf Graph Lifetime: (Level {} -> {}) {s} \n", .{ bufLevelLifetime.firstLevel, bufLevelLifetime.lastLevel, bufName });
            }

            // Texture Debug
            for (0..graphOptimizer.texLevelLifetimes.getLength()) |i| {
                const texLevelLifetime = graphOptimizer.texLevelLifetimes.getByIndex(@intCast(i));
                const texName = try resourceRegistry.getTextureName(texLevelLifetime.tex);
                std.debug.print("- Tex Graph Lifetime: (Level {} -> {}) {s}\n", .{ texLevelLifetime.firstLevel, texLevelLifetime.lastLevel, texName });
            }

            std.debug.print("\n", .{});
        }

        // Extend GraphNodes to GraphMemoryNodes
        for (graphExtractor.orderedPasses.getConstItems()) |graphNode| {
            const accessRange = resourceExtractor.passAccessRanges.getByKey(graphNode.pass.val());

            var bornBytes: u64 = 0;
            var dyingBytes: u64 = 0;

            // Buffers
            for (accessRange.firstBuf..accessRange.lastBuf) |bufIndex| {
                const bufAccess = resourceExtractor.bufAccesses.buffer[bufIndex];
                const bufKey1: u16 = bufAccess.bufInput.val();
                const bufKey2: ?u16 = if (bufAccess.bufOutput) |bufOutput| bufOutput.val() else null;

                // Check Input Buffer Bytes
                if (resourceExtractor.bufMemSize.isKeyUsed(bufKey1) == true) { // Only Transient were filled!
                    const buf1LevelLifetime = graphOptimizer.bufLevelLifetimes.getByKey(bufKey1);
                    if (buf1LevelLifetime.firstLevel == graphNode.level and buf1LevelLifetime.lastLevel != graphNode.level) bornBytes += resourceExtractor.bufMemSize.getByKey(bufKey1);
                    if (buf1LevelLifetime.lastLevel == graphNode.level and buf1LevelLifetime.firstLevel != graphNode.level) dyingBytes += resourceExtractor.bufMemSize.getByKey(bufKey1);
                }

                // Check Output Buffer Bytes
                if (bufKey2) |key2| {
                    if (resourceExtractor.bufMemSize.isKeyUsed(key2) == true) { // Only Transient were filled!
                        const buf2LevelLifetime = graphOptimizer.bufLevelLifetimes.getByKey(key2);
                        if (buf2LevelLifetime.firstLevel == graphNode.level and buf2LevelLifetime.lastLevel != graphNode.level) bornBytes += resourceExtractor.bufMemSize.getByKey(key2);
                        if (buf2LevelLifetime.lastLevel == graphNode.level and buf2LevelLifetime.firstLevel != graphNode.level) dyingBytes += resourceExtractor.bufMemSize.getByKey(key2);
                    }
                }
            }

            // Textures
            for (accessRange.firstTex..accessRange.lastTex) |texIndex| {
                const texAccess = resourceExtractor.texAccesses.buffer[texIndex];
                const texKey1: u16 = texAccess.texInput.val();
                const texKey2: ?u16 = if (texAccess.texOutput) |texOutput| texOutput.val() else null;

                // Check Input Texture Bytes
                if (resourceExtractor.texMemSize.isKeyUsed(texKey1) == true) { // Only Transient were filled!
                    const tex1LevelLifetime = graphOptimizer.texLevelLifetimes.getByKey(texKey1);
                    if (tex1LevelLifetime.firstLevel == graphNode.level and tex1LevelLifetime.lastLevel != graphNode.level) bornBytes += resourceExtractor.texMemSize.getByKey(texKey1);
                    if (tex1LevelLifetime.lastLevel == graphNode.level and tex1LevelLifetime.firstLevel != graphNode.level) dyingBytes += resourceExtractor.texMemSize.getByKey(texKey1);
                }

                // Check Output Buffer Bytes
                if (texKey2) |key2| {
                    if (resourceExtractor.texMemSize.isKeyUsed(key2) == true) { // Only Transient were filled!
                        const tex2LevelLifetime = graphOptimizer.texLevelLifetimes.getByKey(key2);
                        if (tex2LevelLifetime.firstLevel == graphNode.level and tex2LevelLifetime.lastLevel != graphNode.level) bornBytes += resourceExtractor.texMemSize.getByKey(key2);
                        if (tex2LevelLifetime.lastLevel == graphNode.level and tex2LevelLifetime.firstLevel != graphNode.level) dyingBytes += resourceExtractor.texMemSize.getByKey(key2);
                    }
                }
            }

            const castedBornBytes: i64 = @intCast(bornBytes);
            const castedDyingBytes: i64 = @intCast(dyingBytes);

            const graphMemNode = GraphMemoryNode{ .level = graphNode.level, .pass = graphNode.pass, .memWeight = castedBornBytes - castedDyingBytes };
            graphOptimizer.graphMemNodes.append(graphMemNode) catch std.debug.print("ERROR: 4.5.PassOptimizer: Append to graphMemNodes failed!", .{});
        }

        // Sort first by Level then by Memory Byte Weight
        graphOptimizer.graphMemNodes.selectionSort(greaterGraphMemNode);

        for (graphOptimizer.graphMemNodes.constSlice()) |graphMemNode| {
            const graphPassKey = graphMemNode.pass.val();
            graphOptimizer.optimizedGraph.upsert(graphPassKey, graphMemNode);
        }

        // Debug Output 3
        if (rc.FRAME_GRAPH_DEBUG) {
            for (graphOptimizer.optimizedGraph.getConstItems(), 0..) |pass, i| {
                const passName = try resourceRegistry.getPassName(pass.pass);
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
