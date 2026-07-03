const PassLifetime = @import("../../frameBuild/components.zig").PassLifetime;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const OptimizerData = @import("../4.5_Optimizer/OptimizerData.zig").OptimizerData;
const LifetimeData = @import("LifetimeData.zig").LifetimeData;
const AccessData = @import("../1.5_Access/AccessData.zig").AccessData;

// Step 5

pub const LifetimeSys = struct {
    pub fn assignResourceLifetimes(lifetimeData: *LifetimeData, optimizerData: *const OptimizerData, accessData: *const AccessData, registryData: *const RegistryData) !void {
        lifetimeData.bufLifetimes.clear();
        lifetimeData.texLifetimes.clear();

        // Assign Buffers Lifetime
        for (accessData.bufAccesses.constSlice()) |bufAccess| {
            const bufInput = bufAccess.input;
            const passPosition = optimizerData.optimizedGraph.getIndexByKey(bufAccess.pass);

            // Input
            if (lifetimeData.bufLifetimes.isKeyUsed(bufInput) == false) {
                lifetimeData.bufLifetimes.upsert(bufInput, PassLifetime{ .earliest = passPosition, .latest = passPosition });
            } else {
                var bufLifetime = lifetimeData.bufLifetimes.getPtrByKey(bufInput);
                if (passPosition < bufLifetime.earliest) bufLifetime.earliest = passPosition;
                if (passPosition > bufLifetime.latest) bufLifetime.latest = passPosition;
            }
            // Output
            const bufOutput = bufAccess.output orelse continue;
            if (lifetimeData.bufLifetimes.isKeyUsed(bufOutput) == false) {
                lifetimeData.bufLifetimes.upsert(bufOutput, PassLifetime{ .earliest = passPosition, .latest = passPosition });
            } else {
                var bufLifetime = lifetimeData.bufLifetimes.getPtrByKey(bufOutput);
                if (passPosition < bufLifetime.earliest) bufLifetime.earliest = passPosition;
                if (passPosition > bufLifetime.latest) bufLifetime.latest = passPosition;
            }
        }

        // Assign texture Lifetime
        for (accessData.texAccesses.constSlice()) |texAccess| {
            const texInput = texAccess.input;
            const passPosition = optimizerData.optimizedGraph.getIndexByKey(texAccess.pass);
            // Input
            if (lifetimeData.texLifetimes.isKeyUsed(texInput) == false) {
                lifetimeData.texLifetimes.upsert(texInput, PassLifetime{ .earliest = passPosition, .latest = passPosition });
            } else {
                var texLifetime = lifetimeData.texLifetimes.getPtrByKey(texInput);
                if (passPosition < texLifetime.earliest) texLifetime.earliest = passPosition;
                if (passPosition > texLifetime.latest) texLifetime.latest = passPosition;
            }
            // Output
            const texOutput = texAccess.output orelse continue;
            if (lifetimeData.texLifetimes.isKeyUsed(texOutput) == false) {
                lifetimeData.texLifetimes.upsert(texOutput, PassLifetime{ .earliest = passPosition, .latest = passPosition });
            } else {
                var texLifetime = lifetimeData.texLifetimes.getPtrByKey(texOutput);
                if (passPosition < texLifetime.earliest) texLifetime.earliest = passPosition;
                if (passPosition > texLifetime.latest) texLifetime.latest = passPosition;
            }
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.LifetimeExtractor: \n", .{});

            // Buffer Debug
            for (0..lifetimeData.bufLifetimes.getLength()) |i| {
                const bufLifetime = lifetimeData.bufLifetimes.getByIndex(@intCast(i));
                const earliestPass = optimizerData.optimizedGraph.getConstItems()[bufLifetime.earliest].pass;
                const latestPass = optimizerData.optimizedGraph.getConstItems()[bufLifetime.latest].pass;

                const bufPassId = lifetimeData.bufLifetimes.getKeyByIndex(@intCast(i));
                const bufName = try registryData.getBufferName(bufPassId);
                const earliestName = try registryData.getPassName(earliestPass);
                const latestName = try registryData.getPassName(latestPass);
                std.debug.print("- Buf Lifetime: {s}: ({} -> {}) ({s} -> {s})\n", .{ bufName, bufLifetime.earliest, bufLifetime.latest, earliestName, latestName });
            }

            // Texture Debug
            for (0..lifetimeData.texLifetimes.getLength()) |i| {
                const texLifetime = lifetimeData.texLifetimes.getByIndex(@intCast(i));
                const earliestPass = optimizerData.optimizedGraph.getConstItems()[texLifetime.earliest].pass;
                const latestPass = optimizerData.optimizedGraph.getConstItems()[texLifetime.latest].pass;

                const texPassId = lifetimeData.texLifetimes.getKeyByIndex(@intCast(i));
                const texName = try registryData.getTextureName(texPassId);
                const earliestName = try registryData.getPassName(earliestPass);
                const latestName = try registryData.getPassName(latestPass);
                std.debug.print("- Tex Lifetime: {s}: ({} -> {}) ({s} -> {s})\n", .{ texName, texLifetime.earliest, texLifetime.latest, earliestName, latestName });
            }

            std.debug.print("\n", .{});
        }
    }
};
