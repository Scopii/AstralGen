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

        // Transient Buffer Group Lifetime Merge
        for (mapperData.bufGroupsTransient.getConstItems()) |group| {
            const firstBufPassId = mapperData.bufMapTransient.getKeyByIndex(@intCast(group.firstMapIndex));
            const firstLifetime = lifetimeData.bufLifetimes.getByKey(firstBufPassId);

            var earliest = firstLifetime.earliest;
            var latest = firstLifetime.latest;

            for (group.firstMapIndex..group.lastMapIndex + 1) |mapIndex| {
                const bufPassId = mapperData.bufMapTransient.getKeyByIndex(@intCast(mapIndex));
                const bufLifetime = lifetimeData.bufLifetimes.getByKey(bufPassId);

                if (bufLifetime.earliest < earliest) earliest = bufLifetime.earliest;
                if (bufLifetime.latest > latest) latest = bufLifetime.latest;
            }
            const groupLifetime = BufGroupLifetime{ .rootBuf = group.rootBuf, .earliest = earliest, .latest = latest };
            mergerData.transientBufGroupLifetimes.appendAssumeCapacity(groupLifetime);
        }

        // mergerData.transientBufGroupLifetimes.defeatingQuicksort(lessThanGroup);
        mergerData.transientBufGroupLifetimes.selectionSort(greaterGroup);

        // Transient Texture Group Lifetime Merge
        for (mapperData.texGroupsTransient.getConstItems()) |group| {
            const firstTexPassId = mapperData.texMapTransient.getKeyByIndex(@intCast(group.firstMapIndex));
            const firstLifetime = lifetimeData.texLifetimes.getByKey(firstTexPassId);

            var earliest = firstLifetime.earliest;
            var latest = firstLifetime.latest;

            for (group.firstMapIndex..group.lastMapIndex + 1) |mapIndex| {
                const texPassId = mapperData.texMapTransient.getKeyByIndex(@intCast(mapIndex));
                const texLifetime = lifetimeData.texLifetimes.getByKey(texPassId);

                if (texLifetime.earliest < earliest) earliest = texLifetime.earliest;
                if (texLifetime.latest > latest) latest = texLifetime.latest;
            }
            const groupLifetime = TexGroupLifetime{ .rootTex = group.rootTex, .earliest = earliest, .latest = latest };
            mergerData.transientTexGroupLifetimes.appendAssumeCapacity(groupLifetime);
        }

        // mergerData.transientTexGroupLifetimes.defeatingQuicksort(lessThanGroup);
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

fn lessThanGroup(group1: anytype, group2: anytype) bool {
    if (group1.earliest != group2.earliest) return group1.earliest < group2.earliest;
    return group1.latest < group2.latest;
}

fn greaterGroup(group1: anytype, group2: anytype) bool {
    if (group1.earliest != group2.earliest) return group1.earliest > group2.earliest;
    return group1.latest > group2.latest;
}
