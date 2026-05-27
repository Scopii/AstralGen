const TexLevelLifetime = @import("../../frameBuild/components.zig").TexLevelLifetime;
const BufLevelLifetime = @import("../../frameBuild/components.zig").BufLevelLifetime;
const GraphMemoryNode = @import("../../frameBuild/components.zig").GraphMemoryNode;
const TextureEnum = @import("../../frameBuild/enums.zig").TextureEnum;
const BufferEnum = @import("../../frameBuild/enums.zig").BufferEnum;
const PassEnum = @import("../../frameBuild/enums.zig").PassEnum;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const ResourceExtractorData = @import("../2_resourceExtractor/ResourceExtractorData.zig").ResourceExtractorData;
const GraphOptimizerData = @import("../4.5_graphOptimizer/GraphOptimizerData.zig").GraphOptimizerData;
const GraphExtractorData = @import("../4_graphExtractor/GraphExtractorData.zig").GraphExtractorData;

const resolveBufferEnum = @import("../5.1_resourceMapper/ResourceMapperSys.zig").resolveBufferEnum;
const resolveTextureEnum = @import("../5.1_resourceMapper/ResourceMapperSys.zig").resolveTextureEnum;

// Step 4.5

pub const GraphOptimizerSys = struct {
    pub fn assignResourceLevels(graphOptimizer: *GraphOptimizerData, graphExtractor: *const GraphExtractorData, resourceExtractor: *const ResourceExtractorData) !void {
        graphOptimizer.bufLevelLifetimes.clear();
        graphOptimizer.texLevelLifetimes.clear();

        graphOptimizer.bufMemSize.clear();
        graphOptimizer.texMemSize.clear();

        graphOptimizer.graphMemNodes.clear();
        graphOptimizer.optimizedGraph.clear();

        // Assign Buffers Lifetime
        for (resourceExtractor.bufAccesses.constSlice()) |bufAccess| {
            const bufInputKey = @intFromEnum(bufAccess.bufInput);
            const graphLevel = graphExtractor.orderedPasses.getByKey(@intFromEnum(bufAccess.passEnum)).level;

            if (graphOptimizer.bufLevelLifetimes.isKeyUsed(bufInputKey) == false) {
                const bufLevelLifetime = BufLevelLifetime{ .bufEnum = bufAccess.bufInput, .firstLevel = graphLevel, .lastLevel = graphLevel };
                graphOptimizer.bufLevelLifetimes.upsert(bufInputKey, bufLevelLifetime);
            } else {
                var bufLevelLifetime = graphOptimizer.bufLevelLifetimes.getPtrByKey(bufInputKey);
                if (graphLevel < bufLevelLifetime.firstLevel) bufLevelLifetime.firstLevel = graphLevel;
                if (graphLevel > bufLevelLifetime.lastLevel) bufLevelLifetime.lastLevel = graphLevel;
            }
        }

        for (resourceExtractor.bufAccesses.constSlice()) |bufAccess| {
            const bufOutput = bufAccess.bufOutput orelse continue;
            const bufOutputKey = @intFromEnum(bufOutput);
            const graphLevel = graphExtractor.orderedPasses.getByKey(@intFromEnum(bufAccess.passEnum)).level;

            if (graphOptimizer.bufLevelLifetimes.isKeyUsed(bufOutputKey) == false) {
                const bufLevelLifetime = BufLevelLifetime{ .bufEnum = bufOutput, .firstLevel = graphLevel, .lastLevel = graphLevel };
                graphOptimizer.bufLevelLifetimes.upsert(bufOutputKey, bufLevelLifetime);
            } else {
                var bufLevelLifetime = graphOptimizer.bufLevelLifetimes.getPtrByKey(bufOutputKey);
                if (graphLevel < bufLevelLifetime.firstLevel) bufLevelLifetime.firstLevel = graphLevel;
                if (graphLevel > bufLevelLifetime.lastLevel) bufLevelLifetime.lastLevel = graphLevel;
            }
        }

        // Assign texture Lifetime
        for (resourceExtractor.texAccesses.constSlice()) |texAccess| {
            const texInputKey = @intFromEnum(texAccess.texInput);
            const graphLevel = graphExtractor.orderedPasses.getByKey(@intFromEnum(texAccess.passEnum)).level;

            if (graphOptimizer.texLevelLifetimes.isKeyUsed(texInputKey) == false) {
                const texLevelLifetime = TexLevelLifetime{ .texEnum = texAccess.texInput, .firstLevel = graphLevel, .lastLevel = graphLevel };
                graphOptimizer.texLevelLifetimes.upsert(texInputKey, texLevelLifetime);
            } else {
                var texLevelLifetime = graphOptimizer.texLevelLifetimes.getPtrByKey(texInputKey);
                if (graphLevel < texLevelLifetime.firstLevel) texLevelLifetime.firstLevel = graphLevel;
                if (graphLevel > texLevelLifetime.lastLevel) texLevelLifetime.lastLevel = graphLevel;
            }
        }

        for (resourceExtractor.texAccesses.constSlice()) |texAccess| {
            const texOutput = texAccess.texOutput orelse continue;
            const texOutputKey = @intFromEnum(texOutput);
            const graphLevel = graphExtractor.orderedPasses.getByKey(@intFromEnum(texAccess.passEnum)).level;

            if (graphOptimizer.texLevelLifetimes.isKeyUsed(texOutputKey) == false) {
                const texLevelLifetime = TexLevelLifetime{ .texEnum = texOutput, .firstLevel = graphLevel, .lastLevel = graphLevel };
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
                const castedIndex: u32 = @intCast(i);
                const bufLevelLifetime = graphOptimizer.bufLevelLifetimes.getByIndex(castedIndex);
                std.debug.print("- Buf Graph Lifetime: (Level {} -> {}) {s} \n", .{ bufLevelLifetime.firstLevel, bufLevelLifetime.lastLevel, @tagName(bufLevelLifetime.bufEnum) });
            }

            // Texture Debug
            for (0..graphOptimizer.texLevelLifetimes.getLength()) |i| {
                const castedIndex: u32 = @intCast(i);
                const texLevelLifetime = graphOptimizer.texLevelLifetimes.getByIndex(castedIndex);
                std.debug.print("- Tex Graph Lifetime: (Level {} -> {}) {s}\n", .{ texLevelLifetime.firstLevel, texLevelLifetime.lastLevel, @tagName(texLevelLifetime.texEnum) });
            }

            std.debug.print("\n", .{});
        }

        // Give Every Buffer Memory Size
        for (resourceExtractor.bufAccesses.constSlice()) |bufAccess| {
            const bufKey1: u16 = @intCast(@intFromEnum(bufAccess.bufInput));

            if (graphOptimizer.bufLevelLifetimes.isKeyUsed(bufKey1) == true) {
                const bufDesc = try resolveBufferEnum(bufAccess.bufInput);

                switch (bufDesc.share) {
                    .transient => graphOptimizer.bufMemSize.upsert(@intFromEnum(bufAccess.bufInput), bufDesc.guessMemoryCost()),
                    .persistent => {},
                }
            }

            const bufKey2: ?u16 = if (bufAccess.bufOutput) |bufOutput| @intCast(@intFromEnum(bufOutput)) else null;

            if (bufKey2 != null and graphOptimizer.bufLevelLifetimes.isKeyUsed(bufKey2.?) == true) {
                const bufDesc = try resolveBufferEnum(bufAccess.bufOutput.?);

                switch (bufDesc.share) {
                    .transient => graphOptimizer.bufMemSize.upsert(bufKey2.?, bufDesc.guessMemoryCost()),
                    .persistent => {},
                }
            }
        }

        // Give Every Texture Memory Size
        for (resourceExtractor.texAccesses.constSlice()) |texAccess| {
            const texKey1: u16 = @intCast(@intFromEnum(texAccess.texInput));

            if (graphOptimizer.texLevelLifetimes.isKeyUsed(texKey1) == true) {
                const texDesc = try resolveTextureEnum(texAccess.texInput);

                switch (texDesc.share) {
                    .transient => graphOptimizer.texMemSize.upsert(@intFromEnum(texAccess.texInput), texDesc.guessMemoryCost()),
                    .persistent => {},
                }
            }

            const texKey2: ?u16 = if (texAccess.texOutput) |texOutput| @intCast(@intFromEnum(texOutput)) else null;

            if (texKey2 != null and graphOptimizer.texLevelLifetimes.isKeyUsed(texKey2.?) == true) {
                const texDesc = try resolveTextureEnum(texAccess.texOutput.?);

                switch (texDesc.share) {
                    .transient => graphOptimizer.texMemSize.upsert(texKey2.?, texDesc.guessMemoryCost()),
                    .persistent => {},
                }
            }
        }

        // Debug Output 2
        if (rc.FRAME_GRAPH_DEBUG) {
            // Buffer Mem Debug
            for (graphOptimizer.bufMemSize.getConstItems(), 0..) |memSize, i| {
                const castedIndex: u32 = @intCast(i);
                const bufKey: u32 = graphOptimizer.bufMemSize.getKeyByIndex(castedIndex);
                const bufEnum: BufferEnum = @enumFromInt(bufKey);
                std.debug.print(" {}.Buf ({s}) -> Mem {} Bytes\n", .{ i, @tagName(bufEnum), memSize });
            }
            // Texture Mem Debug
            for (graphOptimizer.texMemSize.getConstItems(), 0..) |memSize, i| {
                const castedIndex: u32 = @intCast(i);
                const texKey: u32 = graphOptimizer.texMemSize.getKeyByIndex(castedIndex);
                const texEnum: TextureEnum = @enumFromInt(texKey);
                std.debug.print(" {}.Tex ({s}) -> Mem {} Bytes\n", .{ i, @tagName(texEnum), memSize });
            }
            std.debug.print("\n", .{});
        }

        // Extend GraphNodes to GraphMemoryNodes
        for (graphExtractor.orderedPasses.getConstItems()) |graphNode| {
            const passKey = @intFromEnum(graphNode.passEnum);
            const accessRange = resourceExtractor.passAccessRanges.getByKey(passKey);

            var bornBytes: u64 = 0;
            var dyingBytes: u64 = 0;

            // Buffers
            for (accessRange.firstBuf..accessRange.lastBuf) |bufIndex| {
                const bufAccess = resourceExtractor.bufAccesses.buffer[bufIndex];
                const bufKey1: u16 = @intCast(@intFromEnum(bufAccess.bufInput));
                const bufKey2: ?u16 = if (bufAccess.bufOutput) |bufOutput| @intCast(@intFromEnum(bufOutput)) else null;

                // Check Input Buffer Bytes
                if (graphOptimizer.bufMemSize.isKeyUsed(bufKey1) == true) { // Only Transient were filled!
                    const buf1LevelLifetime = graphOptimizer.bufLevelLifetimes.getByKey(bufKey1);
                    if (buf1LevelLifetime.firstLevel == graphNode.level and buf1LevelLifetime.lastLevel != graphNode.level) bornBytes += graphOptimizer.bufMemSize.getByKey(bufKey1);
                    if (buf1LevelLifetime.lastLevel == graphNode.level and buf1LevelLifetime.firstLevel != graphNode.level) dyingBytes += graphOptimizer.bufMemSize.getByKey(bufKey1);
                }

                // Check Output Buffer Bytes
                if (bufKey2) |key2| {
                    if (graphOptimizer.bufMemSize.isKeyUsed(key2) == true) { // Only Transient were filled!
                        const buf2LevelLifetime = graphOptimizer.bufLevelLifetimes.getByKey(key2);
                        if (buf2LevelLifetime.firstLevel == graphNode.level and buf2LevelLifetime.lastLevel != graphNode.level) bornBytes += graphOptimizer.bufMemSize.getByKey(key2);
                        if (buf2LevelLifetime.lastLevel == graphNode.level and buf2LevelLifetime.firstLevel != graphNode.level) dyingBytes += graphOptimizer.bufMemSize.getByKey(key2);
                    }
                }
            }

            // Textures
            for (accessRange.firstTex..accessRange.lastTex) |texIndex| {
                const texAccess = resourceExtractor.texAccesses.buffer[texIndex];
                const texKey1: u16 = @intCast(@intFromEnum(texAccess.texInput));
                const texKey2: ?u16 = if (texAccess.texOutput) |texOutput| @intCast(@intFromEnum(texOutput)) else null;

                // Check Input Texture Bytes
                if (graphOptimizer.texMemSize.isKeyUsed(texKey1) == true) { // Only Transient were filled!
                    const tex1LevelLifetime = graphOptimizer.texLevelLifetimes.getByKey(texKey1);
                    if (tex1LevelLifetime.firstLevel == graphNode.level and tex1LevelLifetime.lastLevel != graphNode.level) bornBytes += graphOptimizer.texMemSize.getByKey(texKey1);
                    if (tex1LevelLifetime.lastLevel == graphNode.level and tex1LevelLifetime.firstLevel != graphNode.level) dyingBytes += graphOptimizer.texMemSize.getByKey(texKey1);
                }

                // Check Output Buffer Bytes
                if (texKey2) |key2| {
                    if (graphOptimizer.texMemSize.isKeyUsed(key2) == true) { // Only Transient were filled!
                        const tex2LevelLifetime = graphOptimizer.texLevelLifetimes.getByKey(key2);
                        if (tex2LevelLifetime.firstLevel == graphNode.level and tex2LevelLifetime.lastLevel != graphNode.level) bornBytes += graphOptimizer.texMemSize.getByKey(key2);
                        if (tex2LevelLifetime.lastLevel == graphNode.level and tex2LevelLifetime.firstLevel != graphNode.level) dyingBytes += graphOptimizer.texMemSize.getByKey(key2);
                    }
                }
            }

            const castedBornBytes: i64 = @intCast(bornBytes);
            const castedDyingBytes: i64 = @intCast(dyingBytes);

            const graphMemNode = GraphMemoryNode{ .level = graphNode.level, .passEnum = graphNode.passEnum, .memWeight = castedBornBytes - castedDyingBytes };
            graphOptimizer.graphMemNodes.append(graphMemNode) catch std.debug.print("ERROR: 4.5.PassOptimizer: Append to graphMemNodes failed!", .{});
        }

        // Sort first by Level then by Memory Byte Weight
        graphOptimizer.graphMemNodes.selectionSort(greaterGraphMemNode);

        for (graphOptimizer.graphMemNodes.constSlice()) |graphMemNode| {
            const graphPassKey = @intFromEnum(graphMemNode.passEnum);
            graphOptimizer.optimizedGraph.upsert(@intCast(graphPassKey), graphMemNode);
        }

        // Debug Output 3
        if (rc.FRAME_GRAPH_DEBUG) {
            for (graphOptimizer.optimizedGraph.getConstItems(), 0..) |pass, i| {
                std.debug.print("- Nr. {}: {}\n", .{ i, pass });
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
