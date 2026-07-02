const BufGroupLifetime = @import("../../frameBuild/components.zig").BufGroupLifetime;
const TexGroupLifetime = @import("../../frameBuild/components.zig").TexGroupLifetime;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const LifetimeData = @import("../5_Lifetime/LifetimeData.zig").LifetimeData;
const MapperData = @import("../5.1_Mapper/MapperData.zig").MapperData;
const MergerData = @import("MergerData.zig").MergerData;

// Step 5.2

pub const MergerSys = struct {
    pub fn buildPassResources(mergerData: *MergerData, lifetimeData: *const LifetimeData, mapperData: *const MapperData, registryData: *const RegistryData) !void {
        mergerData.transientBufGroupLifetimes.clear();
        mergerData.transientTexGroupLifetimes.clear();

        // NEW Transient Buffer Group Lifetime Merge
        for (mapperData.bufGroupsTransient.getConstItems()) |group| {
            var earliestLife: ?u16 = null;
            var latestLife: ?u16 = null;

            for (group.firstMapIndex..group.lastMapIndex + 1) |mapIndex| {
                const bufKey = mapperData.bufMapTransient.getKeyByIndex(@intCast(mapIndex));
                const bufLifetime = lifetimeData.bufLifetimes.getByKey(bufKey);

                if (earliestLife == null or bufLifetime.earliest < earliestLife.?) earliestLife = bufLifetime.earliest;
                if (latestLife == null or bufLifetime.latest > latestLife.?) latestLife = bufLifetime.latest;
            }
            const groupLifetime = BufGroupLifetime{ .rootBuf = group.rootBuf, .earliest = earliestLife.?, .latest = latestLife.? };
            mergerData.transientBufGroupLifetimes.append(groupLifetime) catch std.debug.print("ERROR: LifetimeMerger: Could not append Transient BufGroupLifetime\n", .{});
        }

        mergerData.transientBufGroupLifetimes.selectionSort(greaterGroup);

        // NEW Transient Texture Group Lifetime Merge
        for (mapperData.texGroupsTransient.getConstItems()) |group| {
            var earliestLife: ?u16 = null;
            var latestLife: ?u16 = null;

            for (group.firstMapIndex..group.lastMapIndex + 1) |mapIndex| {
                const texKey = mapperData.texMapTransient.getKeyByIndex(@intCast(mapIndex));
                const texLifetime = lifetimeData.texLifetimes.getByKey(texKey);

                if (earliestLife == null or texLifetime.earliest < earliestLife.?) earliestLife = texLifetime.earliest;
                if (latestLife == null or texLifetime.latest > latestLife.?) latestLife = texLifetime.latest;
            }
            const groupLifetime = TexGroupLifetime{ .rootTex = group.rootTex, .earliest = earliestLife.?, .latest = latestLife.? };
            mergerData.transientTexGroupLifetimes.append(groupLifetime) catch std.debug.print("ERROR: LifetimeMerger: Could not append Transient BufGroupLifetime\n", .{});
        }

        mergerData.transientTexGroupLifetimes.selectionSort(greaterGroup);

        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.2.LifetimeMerger: \n", .{});
            // Buffer Debug
            for (mergerData.transientBufGroupLifetimes.constSlice(), 0..) |groupLifetime, i| {
                const bufName = try registryData.getBufferName(groupLifetime.rootBuf);
                std.debug.print("- {}. Transient Buf Group (Root {s}) ({} -> {})\n", .{ i, bufName, groupLifetime.earliest, groupLifetime.latest });
            }
            // Texture Debug
            for (mergerData.transientTexGroupLifetimes.constSlice(), 0..) |groupLifetime, i| {
                const texName = try registryData.getTextureName(groupLifetime.rootTex);
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
