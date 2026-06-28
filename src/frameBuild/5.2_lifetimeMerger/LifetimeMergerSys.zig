const BufGroupLifetime = @import("../../frameBuild/components.zig").BufGroupLifetime;
const TexGroupLifetime = @import("../../frameBuild/components.zig").TexGroupLifetime;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const ResourceRegistryData = @import("../0_resourceRegistry/ResourceRegistryData.zig").ResourceRegistryData;
const PassExtractorData = @import("../1_passExtractor/PassExtractorData.zig").PassExtractorData;
const ResourceExtractorData = @import("../2_resourceExtractor/ResourceExtractorData.zig").ResourceExtractorData;
const DependancyExtractorData = @import("../3_dependancyExtractor/DependancyExtractorData.zig").DependancyExtractorData;
const GraphExtractorData = @import("../4_graphExtractor/GraphExtractorData.zig").GraphExtractorData;
const LifetimeExtractorData = @import("../5_lifetimeExtractor/LifetimeExtractorData.zig").LifetimeExtractorData;
const ResourceMapperData = @import("../5.1_resourceMapper/ResourceMapperData.zig").ResourceMapperData;
const LifetimeMergerData = @import("LifetimeMergerData.zig").LifetimeMergerData;

// Step 5.2

pub const LifetimeMergerSys = struct {
    pub fn buildPassResources(
        lifetimeMerger: *LifetimeMergerData,
        lifetimeExtractor: *const LifetimeExtractorData,
        resourceMapper: *const ResourceMapperData,
        resourceRegistry: *const ResourceRegistryData,
    ) !void {
        lifetimeMerger.transientBufGroupLifetimes.clear();
        lifetimeMerger.transientTexGroupLifetimes.clear();

        // NEW Transient Buffer Group Lifetime Merge
        for (resourceMapper.bufGroupsTransient.getConstItems()) |group| {
            var earliestLife: ?u16 = null;
            var latestLife: ?u16 = null;

            for (group.startMapIndex..group.endMapIndex + 1) |mapIndex| {
                const bufKey = resourceMapper.bufMapTransient.getKeyByIndex(@intCast(mapIndex));
                const bufLifetime = lifetimeExtractor.bufLifetimes.getByKey(bufKey);

                if (earliestLife == null or bufLifetime.earliest < earliestLife.?) earliestLife = bufLifetime.earliest;
                if (latestLife == null or bufLifetime.latest > latestLife.?) latestLife = bufLifetime.latest;
            }
            const groupLifetime = BufGroupLifetime{ .rootBuf = group.rootBuf, .earliest = earliestLife.?, .latest = latestLife.? };
            lifetimeMerger.transientBufGroupLifetimes.append(groupLifetime) catch std.debug.print("ERROR: LifetimeMerger: Could not append Transient BufGroupLifetime\n", .{});
        }

        lifetimeMerger.transientBufGroupLifetimes.selectionSort(greaterGroup);

        // NEW Transient Texture Group Lifetime Merge
        for (resourceMapper.texGroupsTransient.getConstItems()) |group| {
            var earliestLife: ?u16 = null;
            var latestLife: ?u16 = null;

            for (group.startMapIndex..group.endMapIndex + 1) |mapIndex| {
                const texKey = resourceMapper.texMapTransient.getKeyByIndex(@intCast(mapIndex));
                const texLifetime = lifetimeExtractor.texLifetimes.getByKey(texKey);

                if (earliestLife == null or texLifetime.earliest < earliestLife.?) earliestLife = texLifetime.earliest;
                if (latestLife == null or texLifetime.latest > latestLife.?) latestLife = texLifetime.latest;
            }
            const groupLifetime = TexGroupLifetime{ .rootTex = group.rootTex, .earliest = earliestLife.?, .latest = latestLife.? };
            lifetimeMerger.transientTexGroupLifetimes.append(groupLifetime) catch std.debug.print("ERROR: LifetimeMerger: Could not append Transient BufGroupLifetime\n", .{});
        }

        lifetimeMerger.transientTexGroupLifetimes.selectionSort(greaterGroup);

        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.2.LifetimeMerger: \n", .{});
            // Buffer Debug
            for (lifetimeMerger.transientBufGroupLifetimes.constSlice(), 0..) |groupLifetime, i| {
                const bufName = try resourceRegistry.getBufferName(groupLifetime.rootBuf);
                std.debug.print("- {}. Transient Buf Group (Root {s}) ({} -> {})\n", .{ i, bufName, groupLifetime.earliest, groupLifetime.latest });
            }
            // Texture Debug
            for (lifetimeMerger.transientTexGroupLifetimes.constSlice(), 0..) |groupLifetime, i| {
                const texName = try resourceRegistry.getTextureName(groupLifetime.rootTex);
                std.debug.print("- {}. Transient Tex Group (Root {s}) ({} -> {})\n", .{ i, texName, groupLifetime.earliest, groupLifetime.latest });
            }
            std.debug.print("\n", .{});
        }
    }
};

fn greaterGroup(group1: anytype, group2: anytype) bool {
    if (group1.earliest != group2.earliest) return group1.earliest > group2.earliest;
    return group1.latest > group2.latest;
}
