const GroupLifetime = @import("../../frameBuild/components.zig").GroupLifetime;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const LifetimeData = @import("../5_Lifetime/LifetimeData.zig").LifetimeData;
const MapperData = @import("../5.1_Mapper/MapperData.zig").MapperData;
const MergerData = @import("MergerData.zig").MergerData;

// Step 5.2

pub const MergerSys = struct {
    pub fn buildPassResources(mergerData: *MergerData, lifetimeData: *const LifetimeData, mapperData: *const MapperData, registryData: *const RegistryData) !void {
        mergerData.transientGroupLifetimes.clear();

        // Transient Buffer Group Lifetime Merge
        for (mapperData.bufGroupsTransient.getConstItems(), 0..) |group, i| {
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
            const groupRootBuf = mapperData.bufGroupsTransient.getKeyByIndex(@intCast(i));
            const groupLifetime = GroupLifetime{ .rootResource = .{ .bufPassId = groupRootBuf }, .earliestPass = earliest, .latestPass = latest };
            mergerData.transientGroupLifetimes.appendAssumeCapacity(groupLifetime);
        }

        // Transient Texture Group Lifetime Merge
        for (mapperData.texGroupsTransient.getConstItems(), 0..) |group, i| {
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
            const groupRootTex = mapperData.texGroupsTransient.getKeyByIndex(@intCast(i));
            const groupLifetime = GroupLifetime{ .rootResource = .{ .texPassId = groupRootTex }, .earliestPass = earliest, .latestPass = latest };
            mergerData.transientGroupLifetimes.appendAssumeCapacity(groupLifetime);
        }

        // mergerData.transientGroupLifetimes.defeatingQuicksort(lessThanGroup);
        mergerData.transientGroupLifetimes.selectionSort(greaterGroup);

        // Debug
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.2.LifetimeMerger: \n", .{});
            for (mergerData.transientGroupLifetimes.constSlice(), 0..) |groupLifetime, i| {
                const resName = switch (groupLifetime.rootResource) {
                    .bufPassId => |rootId| try registryData.getBufferName(rootId),
                    .texPassId => |rootId| try registryData.getTextureName(rootId),
                };
                const resTag = @tagName(groupLifetime.rootResource);
                std.debug.print("- {}. Transient {s} Group (Root {s}) (Pass {} -> Pass {})\n", .{ i, resTag, resName, groupLifetime.earliestPass, groupLifetime.latestPass });
            }
            std.debug.print("\n", .{});
        }
    }
};

fn lessThanGroup(group1: anytype, group2: anytype) bool {
    if (group1.earliestPass != group2.earliestPass) return group1.earliestPass < group2.earliestPass;
    return group1.latestPass < group2.latestPass;
}

fn greaterGroup(group1: anytype, group2: anytype) bool {
    if (group1.earliestPass != group2.earliestPass) return group1.earliestPass > group2.earliestPass;
    return group1.latestPass > group2.latestPass;
}
