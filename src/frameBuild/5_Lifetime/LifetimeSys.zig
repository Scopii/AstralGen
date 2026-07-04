const PassLifetime = @import("../../frameBuild/components.zig").PassLifetime;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const getResKey = @import("../../frameBuild/components.zig").getResKey;
const getResTyp = @import("../../frameBuild/components.zig").getResTyp;

const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const OptimizerData = @import("../4.5_Optimizer/OptimizerData.zig").OptimizerData;
const LifetimeData = @import("LifetimeData.zig").LifetimeData;
const AccessData = @import("../1.5_Access/AccessData.zig").AccessData;

// Step 5

pub const LifetimeSys = struct {
    pub fn assign(lifetimeData: *LifetimeData, optimizerData: *const OptimizerData, accessData: *const AccessData, registryData: *const RegistryData) !void {
        lifetimeData.passLifetimes.clear();

        // Assign Lifetimes
        for (accessData.accesses.constSlice()) |access| {
            const passPosition = optimizerData.optimizedGraph.getIndexByKey(access.pass);
            // Input
            const inputKey = getResKey(access.input);

            if (lifetimeData.passLifetimes.isKeyUsed(inputKey) == false) {
                lifetimeData.passLifetimes.upsert(inputKey, PassLifetime{ .earliest = passPosition, .latest = passPosition });
            } else {
                var lifetime = lifetimeData.passLifetimes.getPtrByKey(inputKey);
                if (passPosition < lifetime.earliest) lifetime.earliest = passPosition;
                if (passPosition > lifetime.latest) lifetime.latest = passPosition;
            }
            // Output
            const outputId = access.output orelse continue;
            const outputKey = getResKey(outputId);

            if (lifetimeData.passLifetimes.isKeyUsed(outputKey) == false) {
                lifetimeData.passLifetimes.upsert(outputKey, PassLifetime{ .earliest = passPosition, .latest = passPosition });
            } else {
                var lifetime = lifetimeData.passLifetimes.getPtrByKey(outputKey);
                if (passPosition < lifetime.earliest) lifetime.earliest = passPosition;
                if (passPosition > lifetime.latest) lifetime.latest = passPosition;
            }
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.LifetimeExtractor: \n", .{});

            for (0..lifetimeData.passLifetimes.getLength()) |i| {
                const lifetime = lifetimeData.passLifetimes.getByIndex(@intCast(i));
                const resKey = lifetimeData.passLifetimes.getKeyByIndex(@intCast(i));
                const resName = switch (getResTyp(resKey)) {
                    .Buf => try registryData.getBufferName(.id(resKey)),
                    .Tex => try registryData.getTextureName(.id(resKey - rc.BUF_MAX)),
                };
                const earliestPass = optimizerData.optimizedGraph.getConstItems()[lifetime.earliest].pass;
                const latestPass = optimizerData.optimizedGraph.getConstItems()[lifetime.latest].pass;
                const earliestName = try registryData.getPassName(earliestPass);
                const latestName = try registryData.getPassName(latestPass);
                const kindTag = @tagName(getResTyp(resKey));
                std.debug.print("- {s} Lifetime: {s}: ({} -> {}) ({s} -> {s})\n", .{ kindTag, resName, lifetime.earliest, lifetime.latest, earliestName, latestName });
            }

            std.debug.print("\n", .{});
        }
    }
};
