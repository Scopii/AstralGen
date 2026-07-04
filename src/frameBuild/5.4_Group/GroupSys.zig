const PhysicalBufLifetime = @import("../../frameBuild/components.zig").PhysicalBufLifetime;
const PhysicalTexLifetime = @import("../../frameBuild/components.zig").PhysicalTexLifetime;
const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const MapperData = @import("../5.1_Mapper/MapperData.zig").MapperData;
const MergerData = @import("../5.2_Merger/MergerData.zig").MergerData;
const GroupData = @import("GroupData.zig").GroupData;

// Step 5.4

pub const GroupSys = struct {
    pub fn buildPassResources(groupData: *GroupData, mergerData: *const MergerData, mapperData: *const MapperData, registryData: *const RegistryData) !void {
        // Cleanup and Prep
        groupData.sharedBufLifetimes.clear();
        groupData.sharedTexLifetimes.clear();

        groupData.bufShareIndexMap.clear();
        groupData.texShareIndexMap.clear();

        groupData.bufClears.clear();
        groupData.texClears.clear();

        // Buffer Group Sharing
        for (mergerData.transientGroupLifetimes.constSlice()) |groupLifetime| {
            switch (groupLifetime.rootResource) {
                .bufPassId => |id| {
                    // Buffer Path
                    const bufGroup = mapperData.bufGroupsTransient.getByKey(id);

                    var candidateIndex: ?u16 = null;

                    if (rc.FRAME_GRAPH_SKIP_SHARING == false) {
                        for (groupData.sharedBufLifetimes.slice(), 0..) |*physLifetime, index| {
                            const physLifetimeDesc = mapperData.bufGroupsTransient.getByKey(physLifetime.bufDescId).bufDesc;

                            // check if physLifetime could extend forwards
                            if (physLifetime.latest < groupLifetime.earliestPass) {
                                // If it can extend check if format fits
                                if (bufDescEqual(&bufGroup.bufDesc, &physLifetimeDesc) == true) {
                                    physLifetime.latest = groupLifetime.latestPass;
                                    candidateIndex = @intCast(index);
                                    break;
                                }
                            }
                        }
                    }

                    if (candidateIndex) |candiate| {
                        // Append Clear (Might be different for backwards extension)
                        groupData.bufClears.append(.{ .sharedBufIndex = candiate, .passAfterClear = bufGroup.rootPass }) catch {
                            std.debug.print("ERROR: 5.4.GroupMerger: Could not Append to bufClears\n", .{});
                        };
                        groupData.bufShareIndexMap.upsert(id, candiate);
                    } else {
                        const physBufLifetime = PhysicalBufLifetime{ .bufDescId = id, .earliest = groupLifetime.earliestPass, .latest = groupLifetime.latestPass };
                        groupData.sharedBufLifetimes.append(physBufLifetime) catch std.debug.print("ERROR: 5.4.GroupMerger: Could not Append to sharedBufLifetimes\n", .{});
                        const newIndex: u16 = @intCast(groupData.sharedBufLifetimes.len - 1);

                        // Append first Clear
                        groupData.bufClears.append(.{ .sharedBufIndex = newIndex, .passAfterClear = bufGroup.rootPass }) catch {
                            std.debug.print("ERROR: 5.4.GroupMerger: Could not Append to texClears\n", .{});
                        };
                        groupData.bufShareIndexMap.upsert(id, newIndex);
                    }
                },
                .texPassId => |id| {
                    // Texture Path
                    const texGroup = mapperData.texGroupsTransient.getByKey(id);

                    var candidateIndex: ?u16 = null;

                    if (rc.FRAME_GRAPH_SKIP_SHARING == false) {
                        for (groupData.sharedTexLifetimes.slice(), 0..) |*physLifetime, index| {
                            const physLifetimeDesc = mapperData.texGroupsTransient.getByKey(physLifetime.texDescId).texDesc;

                            // check if physLifetime could extend forwards
                            if (physLifetime.latest < groupLifetime.earliestPass) {
                                // If it can extend check if format fits
                                if (texDescEqual(&texGroup.texDesc, &physLifetimeDesc) == true) {
                                    physLifetime.latest = groupLifetime.latestPass;
                                    candidateIndex = @intCast(index);
                                    break;
                                }
                            }
                        }
                    }

                    if (candidateIndex) |candiate| {
                        // Append Clear (Might be different for backwards extension)
                        groupData.texClears.append(.{ .sharedTexIndex = candiate, .passAfterClear = texGroup.rootPass }) catch {
                            std.debug.print("ERROR: 5.4.GroupMerger: Could not Append to texClears\n", .{});
                        };
                        groupData.texShareIndexMap.upsert(id, candiate);
                    } else {
                        const physTexLifetime = PhysicalTexLifetime{ .texDescId = id, .earliest = groupLifetime.earliestPass, .latest = groupLifetime.latestPass };
                        groupData.sharedTexLifetimes.append(physTexLifetime) catch std.debug.print("ERROR: 5.4.GroupMerger: Could not Append to sharedTexLifetimes\n", .{});
                        const newIndex: u16 = @intCast(groupData.sharedTexLifetimes.len - 1);

                        // Append first Clear
                        groupData.texClears.append(.{ .sharedTexIndex = newIndex, .passAfterClear = texGroup.rootPass }) catch {
                            std.debug.print("ERROR: 5.4.GroupMerger: Could not Append to texClears\n", .{});
                        };
                        groupData.texShareIndexMap.upsert(id, newIndex);
                    }
                },
            }
        }

        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.4.GroupMerger: \n", .{});
            // Buffer Debug
            for (groupData.sharedBufLifetimes.constSlice(), 0..) |sharedLifetime, i| {
                std.debug.print("- {}. Shared Buf (Liftime {} -> {})\n", .{ i, sharedLifetime.earliest, sharedLifetime.latest });
            }
            std.debug.print("\n", .{});
            for (groupData.bufShareIndexMap.getConstItems(), 0..) |sharedIndex, i| {
                const bufPassId = groupData.bufShareIndexMap.getKeyByIndex(@intCast(i));
                const bufName = try registryData.getBufferName(bufPassId);
                std.debug.print("- {}. Buf {s} -> Shared Index {}\n", .{ i, bufName, sharedIndex });
            }
            std.debug.print("\n", .{});
            // Texture Debug
            for (groupData.sharedTexLifetimes.constSlice(), 0..) |sharedLifetime, i| {
                std.debug.print("- {}. Shared Tex (Liftime {} -> {})\n", .{ i, sharedLifetime.earliest, sharedLifetime.latest });
            }
            std.debug.print("\n", .{});
            for (groupData.texShareIndexMap.getConstItems(), 0..) |sharedIndex, i| {
                const texPassId = groupData.texShareIndexMap.getKeyByIndex(@intCast(i));
                const texName = try registryData.getTextureName(texPassId);
                std.debug.print("- {}. Tex {s} -> Shared Index {}\n", .{ i, texName, sharedIndex });
            }
            std.debug.print("\n", .{});
        }
    }
};

fn bufDescEqual(bufDesc1: *const BufDesc, bufDesc2: *const BufDesc) bool {
    return std.meta.eql(bufDesc1.*, bufDesc2.*);
}

fn texDescEqual(texDesc1: *const TexDesc, texDesc2: *const TexDesc) bool {
    return std.meta.eql(texDesc1.*, texDesc2.*);
}
