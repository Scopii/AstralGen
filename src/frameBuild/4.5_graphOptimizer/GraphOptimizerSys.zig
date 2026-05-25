const TexLevelLifetime = @import("../../frameBuild/components.zig").TexLevelLifetime;
const BufLevelLifetime = @import("../../frameBuild/components.zig").BufLevelLifetime;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const ResourceExtractorData = @import("../2_resourceExtractor/ResourceExtractorData.zig").ResourceExtractorData;
const GraphOptimizerData = @import("../4.5_graphOptimizer/GraphOptimizerData.zig").GraphOptimizerData;
const GraphExtractorData = @import("../4_graphExtractor/GraphExtractorData.zig").GraphExtractorData;

// Step 4.5

pub const GraphOptimizerSys = struct {
    pub fn assignResourceLevels(graphOptimizer: *GraphOptimizerData, graphExtractor: *const GraphExtractorData, resourceExtractor: *const ResourceExtractorData) void {
        graphOptimizer.bufLevelLifetimes.clear();
        graphOptimizer.texLevelLifetimes.clear();

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
                const bufLifetime = graphOptimizer.bufLevelLifetimes.getByIndex(castedIndex);
                std.debug.print("- Buf Lifetime: {s}: (First Level{} -> Last Level {})\n", .{ @tagName(bufLifetime.bufEnum), bufLifetime.firstLevel, bufLifetime.lastLevel });
            }

            // Texture Debug
            for (0..graphOptimizer.texLevelLifetimes.getLength()) |i| {
                const castedIndex: u32 = @intCast(i);
                const texLifetime = graphOptimizer.texLevelLifetimes.getByIndex(castedIndex);
                std.debug.print("- Tex Lifetime: {s}: (First Level{} -> Last Level {})\n", .{ @tagName(texLifetime.texEnum), texLifetime.firstLevel, texLifetime.lastLevel });
            }

            std.debug.print("\n", .{});
        }
    }
};
