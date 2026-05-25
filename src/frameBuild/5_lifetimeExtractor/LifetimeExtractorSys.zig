const GraphExtractorData = @import("../4_graphExtractor/GraphExtractorData.zig").GraphExtractorData;
const LifetimeExtractorData = @import("LifetimeExtractorData.zig").LifetimeExtractorData;
const TextureLifetime = @import("../../frameBuild/components.zig").TextureLifetime;
const BufferLifetime = @import("../../frameBuild/components.zig").BufferLifetime;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const ResourceExtractorData = @import("../2_resourceExtractor/ResourceExtractorData.zig").ResourceExtractorData;

// Step 5

pub const LifetimeExtractorSys = struct {
    pub fn assignResourceLifetimes(lifetimeExtractor: *LifetimeExtractorData, graphExtractor: *const GraphExtractorData, resourceExtractor: *const ResourceExtractorData) void {
        lifetimeExtractor.bufLifetimes.clear();
        lifetimeExtractor.texLifetimes.clear();

        // Assign Buffers Lifetime
        for (resourceExtractor.bufAccesses.constSlice()) |bufAccess| {
            const bufInputKey = @intFromEnum(bufAccess.bufInput);
            const passPosition = graphExtractor.orderedPasses.getIndexByKey(@intFromEnum(bufAccess.passEnum));

            if (lifetimeExtractor.bufLifetimes.isKeyUsed(bufInputKey) == false) {
                const bufLifetime = BufferLifetime{ .bufEnum = bufAccess.bufInput, .earliest = passPosition, .latest = passPosition };
                lifetimeExtractor.bufLifetimes.upsert(bufInputKey, bufLifetime);
            } else {
                var bufLifetime = lifetimeExtractor.bufLifetimes.getPtrByKey(bufInputKey);
                if (passPosition < bufLifetime.earliest) bufLifetime.earliest = passPosition;
                if (passPosition > bufLifetime.latest) bufLifetime.latest = passPosition;
            }
        }

        for (resourceExtractor.bufAccesses.constSlice()) |bufAccess| {
            const bufOutput = bufAccess.bufOutput orelse continue;
            const bufOutputKey = @intFromEnum(bufOutput);
            const passPosition = graphExtractor.orderedPasses.getIndexByKey(@intFromEnum(bufAccess.passEnum));

            if (lifetimeExtractor.bufLifetimes.isKeyUsed(bufOutputKey) == false) {
                const bufLifetime = BufferLifetime{ .bufEnum = bufOutput, .earliest = passPosition, .latest = passPosition };
                lifetimeExtractor.bufLifetimes.upsert(bufOutputKey, bufLifetime);
            } else {
                var bufLifetime = lifetimeExtractor.bufLifetimes.getPtrByKey(bufOutputKey);
                if (passPosition < bufLifetime.earliest) bufLifetime.earliest = passPosition;
                if (passPosition > bufLifetime.latest) bufLifetime.latest = passPosition;
            }
        }

        // Assign texture Lifetime
        for (resourceExtractor.texAccesses.constSlice()) |texAccess| {
            const texInputKey = @intFromEnum(texAccess.texInput);
            const passPosition = graphExtractor.orderedPasses.getIndexByKey(@intFromEnum(texAccess.passEnum));

            if (lifetimeExtractor.texLifetimes.isKeyUsed(texInputKey) == false) {
                const texLifetime = TextureLifetime{ .texEnum = texAccess.texInput, .earliest = passPosition, .latest = passPosition };
                lifetimeExtractor.texLifetimes.upsert(texInputKey, texLifetime);
            } else {
                var texLifetime = lifetimeExtractor.texLifetimes.getPtrByKey(texInputKey);
                if (passPosition < texLifetime.earliest) texLifetime.earliest = passPosition;
                if (passPosition > texLifetime.latest) texLifetime.latest = passPosition;
            }
        }

        for (resourceExtractor.texAccesses.constSlice()) |texAccess| {
            const texOutput = texAccess.texOutput orelse continue;
            const texOutputKey = @intFromEnum(texOutput);
            const passPosition = graphExtractor.orderedPasses.getIndexByKey(@intFromEnum(texAccess.passEnum));

            if (lifetimeExtractor.texLifetimes.isKeyUsed(texOutputKey) == false) {
                const texLifetime = TextureLifetime{ .texEnum = texOutput, .earliest = passPosition, .latest = passPosition };
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
                const castedIndex: u32 = @intCast(i);
                const bufLifetime = lifetimeExtractor.bufLifetimes.getByIndex(castedIndex);
                const earliestPass = graphExtractor.orderedPasses.getConstItems()[bufLifetime.earliest].passEnum;
                const latestPass = graphExtractor.orderedPasses.getConstItems()[bufLifetime.latest].passEnum;
                std.debug.print("- Buf Lifetime: {s}: ({} -> {}) ({} -> {})\n", .{ @tagName(bufLifetime.bufEnum), bufLifetime.earliest, bufLifetime.latest, earliestPass, latestPass });
            }

            // Texture Debug
            for (0..lifetimeExtractor.texLifetimes.getLength()) |i| {
                const castedIndex: u32 = @intCast(i);
                const texLifetime = lifetimeExtractor.texLifetimes.getByIndex(castedIndex);
                const earliestPass = graphExtractor.orderedPasses.getConstItems()[texLifetime.earliest].passEnum;
                const latestPass = graphExtractor.orderedPasses.getConstItems()[texLifetime.latest].passEnum;
                std.debug.print("- Tex Lifetime: {s}: ({} -> {}) ({} -> {})\n", .{ @tagName(texLifetime.texEnum), texLifetime.earliest, texLifetime.latest, earliestPass, latestPass });
            }

            std.debug.print("\n", .{});
        }
    }
};
