const TexLevelLifetime = @import("../../frameBuild/components.zig").TexLevelLifetime;
const BufLevelLifetime = @import("../../frameBuild/components.zig").BufLevelLifetime;
const GraphMemoryNode = @import("../../frameBuild/components.zig").GraphMemoryNode;
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
        optimizerData.bufLevelLifetimes.clear();
        optimizerData.texLevelLifetimes.clear();

        optimizerData.graphMemNodes.clear();
        optimizerData.optimizedGraph.clear();

        // Assign Buffers Lifetime
        for (accessData.bufAccesses.constSlice()) |bufAccess| {
            const bufInputKey = bufAccess.bufInput.val();
            if (resourceData.bufMemSizes.isKeyUsed(bufInputKey) == false) continue; // Only Transient

            const graphLevel = graphData.orderedPasses.getByKey(bufAccess.pass.val()).level;

            if (optimizerData.bufLevelLifetimes.isKeyUsed(bufInputKey) == false) {
                const bufLevelLifetime = BufLevelLifetime{ .buf = bufAccess.bufInput, .firstLevel = graphLevel, .lastLevel = graphLevel };
                optimizerData.bufLevelLifetimes.upsert(bufInputKey, bufLevelLifetime);
            } else {
                var bufLevelLifetime = optimizerData.bufLevelLifetimes.getPtrByKey(bufInputKey);
                if (graphLevel < bufLevelLifetime.firstLevel) bufLevelLifetime.firstLevel = graphLevel;
                if (graphLevel > bufLevelLifetime.lastLevel) bufLevelLifetime.lastLevel = graphLevel;
            }
        }

        for (accessData.bufAccesses.constSlice()) |bufAccess| {
            const bufOutput = bufAccess.bufOutput orelse continue;
            const bufOutputKey = bufOutput.val();
            if (resourceData.bufMemSizes.isKeyUsed(bufOutputKey) == false) continue; // Only Transient

            const graphLevel = graphData.orderedPasses.getByKey(bufAccess.pass.val()).level;

            if (optimizerData.bufLevelLifetimes.isKeyUsed(bufOutputKey) == false) {
                const bufLevelLifetime = BufLevelLifetime{ .buf = bufOutput, .firstLevel = graphLevel, .lastLevel = graphLevel };
                optimizerData.bufLevelLifetimes.upsert(bufOutputKey, bufLevelLifetime);
            } else {
                var bufLevelLifetime = optimizerData.bufLevelLifetimes.getPtrByKey(bufOutputKey);
                if (graphLevel < bufLevelLifetime.firstLevel) bufLevelLifetime.firstLevel = graphLevel;
                if (graphLevel > bufLevelLifetime.lastLevel) bufLevelLifetime.lastLevel = graphLevel;
            }
        }

        // Assign texture Lifetime
        for (accessData.texAccesses.constSlice()) |texAccess| {
            const texInputKey = texAccess.texInput.val();
            if (resourceData.texMemSizeS.isKeyUsed(texInputKey) == false) continue; // Only Transient

            const graphLevel = graphData.orderedPasses.getByKey(texAccess.pass.val()).level;

            if (optimizerData.texLevelLifetimes.isKeyUsed(texInputKey) == false) {
                const texLevelLifetime = TexLevelLifetime{ .tex = texAccess.texInput, .firstLevel = graphLevel, .lastLevel = graphLevel };
                optimizerData.texLevelLifetimes.upsert(texInputKey, texLevelLifetime);
            } else {
                var texLevelLifetime = optimizerData.texLevelLifetimes.getPtrByKey(texInputKey);
                if (graphLevel < texLevelLifetime.firstLevel) texLevelLifetime.firstLevel = graphLevel;
                if (graphLevel > texLevelLifetime.lastLevel) texLevelLifetime.lastLevel = graphLevel;
            }
        }

        for (accessData.texAccesses.constSlice()) |texAccess| {
            const texOutput = texAccess.texOutput orelse continue;
            const texOutputKey = texOutput.val();
            if (resourceData.texMemSizeS.isKeyUsed(texOutputKey) == false) continue; // Only Transient

            const graphLevel = graphData.orderedPasses.getByKey(texAccess.pass.val()).level;

            if (optimizerData.texLevelLifetimes.isKeyUsed(texOutputKey) == false) {
                const texLevelLifetime = TexLevelLifetime{ .tex = texOutput, .firstLevel = graphLevel, .lastLevel = graphLevel };
                optimizerData.texLevelLifetimes.upsert(texOutputKey, texLevelLifetime);
            } else {
                var texLevelLifetime = optimizerData.texLevelLifetimes.getPtrByKey(texOutputKey);
                if (graphLevel < texLevelLifetime.firstLevel) texLevelLifetime.firstLevel = graphLevel;
                if (graphLevel > texLevelLifetime.lastLevel) texLevelLifetime.lastLevel = graphLevel;
            }
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("4.5.GraphOptimizer: \n", .{});

            // Buffer Debug
            for (0..optimizerData.bufLevelLifetimes.getLength()) |i| {
                const bufLevelLifetime = optimizerData.bufLevelLifetimes.getByIndex(@intCast(i));
                const bufName = try registryData.getBufferName(bufLevelLifetime.buf);
                std.debug.print("- Buf Graph Lifetime: (Level {} -> {}) {s} \n", .{ bufLevelLifetime.firstLevel, bufLevelLifetime.lastLevel, bufName });
            }

            // Texture Debug
            for (0..optimizerData.texLevelLifetimes.getLength()) |i| {
                const texLevelLifetime = optimizerData.texLevelLifetimes.getByIndex(@intCast(i));
                const texName = try registryData.getTextureName(texLevelLifetime.tex);
                std.debug.print("- Tex Graph Lifetime: (Level {} -> {}) {s}\n", .{ texLevelLifetime.firstLevel, texLevelLifetime.lastLevel, texName });
            }

            std.debug.print("\n", .{});
        }

        // Extend GraphNodes to GraphMemoryNodes
        for (graphData.orderedPasses.getConstItems()) |graphNode| {
            const accessRange = accessData.passAccessRanges.getByKey(graphNode.pass.val());

            var bornBytes: u64 = 0;
            var dyingBytes: u64 = 0;

            // Buffers
            for (accessRange.firstBuf..accessRange.lastBuf) |bufIndex| {
                const bufAccess = accessData.bufAccesses.buffer[bufIndex];
                const bufKey1: u16 = bufAccess.bufInput.val();

                // Check Input Buffer Bytes
                if (resourceData.bufMemSizes.isKeyUsed(bufKey1) == true) { // Only Transient were filled!
                    const buf1LevelLifetime = optimizerData.bufLevelLifetimes.getByKey(bufKey1);
                    if (buf1LevelLifetime.firstLevel == graphNode.level and buf1LevelLifetime.lastLevel != graphNode.level) bornBytes += resourceData.bufMemSizes.getByKey(bufKey1);
                    if (buf1LevelLifetime.lastLevel == graphNode.level and buf1LevelLifetime.firstLevel != graphNode.level) dyingBytes += resourceData.bufMemSizes.getByKey(bufKey1);
                }

                // Check Output Buffer Bytes
                if (bufAccess.bufOutput) |bufOutput| {
                    const key2 = bufOutput.val();
                    if (resourceData.bufMemSizes.isKeyUsed(key2) == true) { // Only Transient were filled!
                        const buf2LevelLifetime = optimizerData.bufLevelLifetimes.getByKey(key2);
                        if (buf2LevelLifetime.firstLevel == graphNode.level and buf2LevelLifetime.lastLevel != graphNode.level) bornBytes += resourceData.bufMemSizes.getByKey(key2);
                        if (buf2LevelLifetime.lastLevel == graphNode.level and buf2LevelLifetime.firstLevel != graphNode.level) dyingBytes += resourceData.bufMemSizes.getByKey(key2);
                    }
                }
            }

            // Textures
            for (accessRange.firstTex..accessRange.lastTex) |texIndex| {
                const texAccess = accessData.texAccesses.buffer[texIndex];
                const texKey1: u16 = texAccess.texInput.val();

                // Check Input Texture Bytes
                if (resourceData.texMemSizeS.isKeyUsed(texKey1) == true) { // Only Transient were filled!
                    const tex1LevelLifetime = optimizerData.texLevelLifetimes.getByKey(texKey1);
                    if (tex1LevelLifetime.firstLevel == graphNode.level and tex1LevelLifetime.lastLevel != graphNode.level) bornBytes += resourceData.texMemSizeS.getByKey(texKey1);
                    if (tex1LevelLifetime.lastLevel == graphNode.level and tex1LevelLifetime.firstLevel != graphNode.level) dyingBytes += resourceData.texMemSizeS.getByKey(texKey1);
                }

                // Check Output Buffer Bytes
                if (texAccess.texOutput) |texOutput| {
                    const key2 = texOutput.val();
                    if (resourceData.texMemSizeS.isKeyUsed(key2) == true) { // Only Transient were filled!
                        const tex2LevelLifetime = optimizerData.texLevelLifetimes.getByKey(key2);
                        if (tex2LevelLifetime.firstLevel == graphNode.level and tex2LevelLifetime.lastLevel != graphNode.level) bornBytes += resourceData.texMemSizeS.getByKey(key2);
                        if (tex2LevelLifetime.lastLevel == graphNode.level and tex2LevelLifetime.firstLevel != graphNode.level) dyingBytes += resourceData.texMemSizeS.getByKey(key2);
                    }
                }
            }

            const castedBornBytes: i64 = @intCast(bornBytes);
            const castedDyingBytes: i64 = @intCast(dyingBytes);

            const graphMemNode = GraphMemoryNode{ .level = graphNode.level, .pass = graphNode.pass, .memWeight = castedBornBytes - castedDyingBytes };
            optimizerData.graphMemNodes.append(graphMemNode) catch std.debug.print("ERROR: 4.5.PassOptimizer: Append to graphMemNodes failed!", .{});
        }

        // Sort first by Level then by Memory Byte Weight
        optimizerData.graphMemNodes.selectionSort(greaterGraphMemNode);

        for (optimizerData.graphMemNodes.constSlice()) |graphMemNode| {
            const graphPassKey = graphMemNode.pass.val();
            optimizerData.optimizedGraph.upsert(graphPassKey, graphMemNode);
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
