const TextureLifetime = @import("../../frameBuild/components.zig").TextureLifetime;
const BufferLifetime = @import("../../frameBuild/components.zig").BufferLifetime;
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
            const bufInputKey = bufAccess.bufInput.val();
            const passPosition = optimizerData.optimizedGraph.getIndexByKey(bufAccess.pass.val());

            if (lifetimeData.bufLifetimes.isKeyUsed(bufInputKey) == false) {
                lifetimeData.bufLifetimes.upsert(bufInputKey, BufferLifetime{ .buf = bufAccess.bufInput, .earliest = passPosition, .latest = passPosition });
            } else {
                var bufLifetime = lifetimeData.bufLifetimes.getPtrByKey(bufInputKey);
                if (passPosition < bufLifetime.earliest) bufLifetime.earliest = passPosition;
                if (passPosition > bufLifetime.latest) bufLifetime.latest = passPosition;
            }
        }

        for (accessData.bufAccesses.constSlice()) |bufAccess| {
            const bufOutput = bufAccess.bufOutput orelse continue;
            const bufOutputKey = bufOutput.val();
            const passPosition = optimizerData.optimizedGraph.getIndexByKey(bufAccess.pass.val());

            if (lifetimeData.bufLifetimes.isKeyUsed(bufOutputKey) == false) {
                lifetimeData.bufLifetimes.upsert(bufOutputKey, BufferLifetime{ .buf = bufOutput, .earliest = passPosition, .latest = passPosition });
            } else {
                var bufLifetime = lifetimeData.bufLifetimes.getPtrByKey(bufOutputKey);
                if (passPosition < bufLifetime.earliest) bufLifetime.earliest = passPosition;
                if (passPosition > bufLifetime.latest) bufLifetime.latest = passPosition;
            }
        }

        // Assign texture Lifetime
        for (accessData.texAccesses.constSlice()) |texAccess| {
            const texInputKey = texAccess.texInput.val();
            const passPosition = optimizerData.optimizedGraph.getIndexByKey(texAccess.pass.val());

            if (lifetimeData.texLifetimes.isKeyUsed(texInputKey) == false) {
                lifetimeData.texLifetimes.upsert(texInputKey, TextureLifetime{ .tex = texAccess.texInput, .earliest = passPosition, .latest = passPosition });
            } else {
                var texLifetime = lifetimeData.texLifetimes.getPtrByKey(texInputKey);
                if (passPosition < texLifetime.earliest) texLifetime.earliest = passPosition;
                if (passPosition > texLifetime.latest) texLifetime.latest = passPosition;
            }
        }

        for (accessData.texAccesses.constSlice()) |texAccess| {
            const texOutput = texAccess.texOutput orelse continue;
            const texOutputKey = texOutput.val();
            const passPosition = optimizerData.optimizedGraph.getIndexByKey(texAccess.pass.val());

            if (lifetimeData.texLifetimes.isKeyUsed(texOutputKey) == false) {
                lifetimeData.texLifetimes.upsert(texOutputKey, TextureLifetime{ .tex = texOutput, .earliest = passPosition, .latest = passPosition });
            } else {
                var texLifetime = lifetimeData.texLifetimes.getPtrByKey(texOutputKey);
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

                const bufName = try registryData.getBufferName(bufLifetime.buf);
                const earliestName = try registryData.getPassName(earliestPass);
                const latestName = try registryData.getPassName(latestPass);
                std.debug.print("- Buf Lifetime: {s}: ({} -> {}) ({s} -> {s})\n", .{ bufName, bufLifetime.earliest, bufLifetime.latest, earliestName, latestName });
            }

            // Texture Debug
            for (0..lifetimeData.texLifetimes.getLength()) |i| {
                const texLifetime = lifetimeData.texLifetimes.getByIndex(@intCast(i));
                const earliestPass = optimizerData.optimizedGraph.getConstItems()[texLifetime.earliest].pass;
                const latestPass = optimizerData.optimizedGraph.getConstItems()[texLifetime.latest].pass;

                const texName = try registryData.getTextureName(texLifetime.tex);
                const earliestName = try registryData.getPassName(earliestPass);
                const latestName = try registryData.getPassName(latestPass);
                std.debug.print("- Tex Lifetime: {s}: ({} -> {}) ({s} -> {s})\n", .{ texName, texLifetime.earliest, texLifetime.latest, earliestName, latestName });
            }

            std.debug.print("\n", .{});
        }
    }
};
