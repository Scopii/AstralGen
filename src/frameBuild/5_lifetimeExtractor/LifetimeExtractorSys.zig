const TextureLifetime = @import("../../frameBuild/components.zig").TextureLifetime;
const BufferLifetime = @import("../../frameBuild/components.zig").BufferLifetime;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const ResourceRegistryData = @import("../0_resourceRegistry/ResourceRegistryData.zig").ResourceRegistryData;
const ResourceExtractorData = @import("../2_resourceExtractor/ResourceExtractorData.zig").ResourceExtractorData;
const GraphOptimizerData = @import("../4.5_graphOptimizer/GraphOptimizerData.zig").GraphOptimizerData;
const LifetimeExtractorData = @import("LifetimeExtractorData.zig").LifetimeExtractorData;
const AccessExtractorData = @import("../1.5_accessExtractor/AccessExtractorData.zig").AccessExtractorData;

// Step 5

pub const LifetimeExtractorSys = struct {
    pub fn assignResourceLifetimes(
        lifetimeExtractor: *LifetimeExtractorData,
        graphOptimizer: *const GraphOptimizerData,
        accessExtractor: *const AccessExtractorData,
        resourceRegistry: *const ResourceRegistryData,
    ) !void {
        lifetimeExtractor.bufLifetimes.clear();
        lifetimeExtractor.texLifetimes.clear();

        // Assign Buffers Lifetime
        for (accessExtractor.bufAccesses.constSlice()) |bufAccess| {
            const bufInputKey = bufAccess.bufInput.val();
            const passPosition = graphOptimizer.optimizedGraph.getIndexByKey(bufAccess.pass.val());

            if (lifetimeExtractor.bufLifetimes.isKeyUsed(bufInputKey) == false) {
                const bufLifetime = BufferLifetime{ .buf = bufAccess.bufInput, .earliest = passPosition, .latest = passPosition };
                lifetimeExtractor.bufLifetimes.upsert(bufInputKey, bufLifetime);
            } else {
                var bufLifetime = lifetimeExtractor.bufLifetimes.getPtrByKey(bufInputKey);
                if (passPosition < bufLifetime.earliest) bufLifetime.earliest = passPosition;
                if (passPosition > bufLifetime.latest) bufLifetime.latest = passPosition;
            }
        }

        for (accessExtractor.bufAccesses.constSlice()) |bufAccess| {
            const bufOutput = bufAccess.bufOutput orelse continue;
            const bufOutputKey = bufOutput.val();
            const passPosition = graphOptimizer.optimizedGraph.getIndexByKey(bufAccess.pass.val());

            if (lifetimeExtractor.bufLifetimes.isKeyUsed(bufOutputKey) == false) {
                const bufLifetime = BufferLifetime{ .buf = bufOutput, .earliest = passPosition, .latest = passPosition };
                lifetimeExtractor.bufLifetimes.upsert(bufOutputKey, bufLifetime);
            } else {
                var bufLifetime = lifetimeExtractor.bufLifetimes.getPtrByKey(bufOutputKey);
                if (passPosition < bufLifetime.earliest) bufLifetime.earliest = passPosition;
                if (passPosition > bufLifetime.latest) bufLifetime.latest = passPosition;
            }
        }

        // Assign texture Lifetime
        for (accessExtractor.texAccesses.constSlice()) |texAccess| {
            const texInputKey = texAccess.texInput.val();
            const passPosition = graphOptimizer.optimizedGraph.getIndexByKey(texAccess.pass.val());

            if (lifetimeExtractor.texLifetimes.isKeyUsed(texInputKey) == false) {
                const texLifetime = TextureLifetime{ .tex = texAccess.texInput, .earliest = passPosition, .latest = passPosition };
                lifetimeExtractor.texLifetimes.upsert(texInputKey, texLifetime);
            } else {
                var texLifetime = lifetimeExtractor.texLifetimes.getPtrByKey(texInputKey);
                if (passPosition < texLifetime.earliest) texLifetime.earliest = passPosition;
                if (passPosition > texLifetime.latest) texLifetime.latest = passPosition;
            }
        }

        for (accessExtractor.texAccesses.constSlice()) |texAccess| {
            const texOutput = texAccess.texOutput orelse continue;
            const texOutputKey = texOutput.val();
            const passPosition = graphOptimizer.optimizedGraph.getIndexByKey(texAccess.pass.val());

            if (lifetimeExtractor.texLifetimes.isKeyUsed(texOutputKey) == false) {
                const texLifetime = TextureLifetime{ .tex = texOutput, .earliest = passPosition, .latest = passPosition };
                lifetimeExtractor.texLifetimes.upsert(texOutputKey, texLifetime);
            } else {
                var texLifetime = lifetimeExtractor.texLifetimes.getPtrByKey(texOutputKey);
                if (passPosition < texLifetime.earliest) texLifetime.earliest = passPosition;
                if (passPosition > texLifetime.latest) texLifetime.latest = passPosition;
            }
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.LifetimeExtractor: \n", .{});

            // Buffer Debug
            for (0..lifetimeExtractor.bufLifetimes.getLength()) |i| {
                const bufLifetime = lifetimeExtractor.bufLifetimes.getByIndex(@intCast(i));
                const earliestPass = graphOptimizer.optimizedGraph.getConstItems()[bufLifetime.earliest].pass;
                const latestPass = graphOptimizer.optimizedGraph.getConstItems()[bufLifetime.latest].pass;

                const bufName = try resourceRegistry.getBufferName(bufLifetime.buf);
                const earliestName = try resourceRegistry.getPassName(earliestPass);
                const latestName = try resourceRegistry.getPassName(latestPass);
                std.debug.print("- Buf Lifetime: {s}: ({} -> {}) ({s} -> {s})\n", .{ bufName, bufLifetime.earliest, bufLifetime.latest, earliestName, latestName });
            }

            // Texture Debug
            for (0..lifetimeExtractor.texLifetimes.getLength()) |i| {
                const texLifetime = lifetimeExtractor.texLifetimes.getByIndex(@intCast(i));
                const earliestPass = graphOptimizer.optimizedGraph.getConstItems()[texLifetime.earliest].pass;
                const latestPass = graphOptimizer.optimizedGraph.getConstItems()[texLifetime.latest].pass;

                const texName = try resourceRegistry.getTextureName(texLifetime.tex);
                const earliestName = try resourceRegistry.getPassName(earliestPass);
                const latestName = try resourceRegistry.getPassName(latestPass);
                std.debug.print("- Tex Lifetime: {s}: ({} -> {}) ({s} -> {s})\n", .{ texName, texLifetime.earliest, texLifetime.latest, earliestName, latestName });
            }

            std.debug.print("\n", .{});
        }
    }
};
