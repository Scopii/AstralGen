const PhysicalResLifetime = @import("../../frameBuild/components.zig").PhysicalResLifetime;
const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const ResDesc = @import("../../frameBuild/components.zig").ResDesc;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const getResTyp = @import("../../frameBuild/components.zig").getResTyp;

const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const MapperData = @import("../5.1_Mapper/MapperData.zig").MapperData;
const GroupData = @import("GroupData.zig").GroupData;

// Step 5.4

pub const GroupSys = struct {
    pub fn build(groupData: *GroupData, mapperData: *const MapperData, registryData: *const RegistryData) !void {
        // Cleanup and Prep
        groupData.sharedResLifetimes.clear();
        groupData.shareIndexMap.clear();
        groupData.resourceClears.clear();

        // Buffer Group Sharing
        for (mapperData.transientGroupLifetimes.constSlice()) |groupLifetime| {
            const group = mapperData.transientGroups.getByKey(groupLifetime.rootResource);

            var candidateIndex: ?u16 = null;

            if (rc.FRAME_GRAPH_SKIP_SHARING == false) {
                for (groupData.sharedResLifetimes.slice(), 0..) |*physLifetime, index| {
                    const physGroupDesc = mapperData.transientGroups.getByKey(physLifetime.resKey).desc;

                    // check if physLifetime could extend forwards
                    if (physLifetime.latest < groupLifetime.earliestPass) {
                        // If it can extend check if format fits
                        if (resDescEqual(&group.desc, &physGroupDesc) == true) {
                            physLifetime.latest = groupLifetime.latestPass;
                            candidateIndex = @intCast(index);
                            break;
                        }
                    }
                }
            }

            if (candidateIndex) |candiate| {
                // Append Clear (Might be different for backwards extension)
                groupData.resourceClears.append(.{ .sharedIndex = candiate, .passAfterClear = group.rootPass }) catch {
                    std.debug.print("ERROR: 5.4.GroupMerger: Could not Append to bufClears\n", .{});
                };
                groupData.shareIndexMap.upsert(groupLifetime.rootResource, candiate);
            } else {
                const physBufLifetime = PhysicalResLifetime{ .resKey = groupLifetime.rootResource, .earliest = groupLifetime.earliestPass, .latest = groupLifetime.latestPass };
                groupData.sharedResLifetimes.append(physBufLifetime) catch std.debug.print("ERROR: 5.4.GroupMerger: Could not Append to sharedBufLifetimes\n", .{});
                const newIndex: u16 = @intCast(groupData.sharedResLifetimes.len - 1);

                // Append first Clear
                groupData.resourceClears.append(.{ .sharedIndex = newIndex, .passAfterClear = group.rootPass }) catch {
                    std.debug.print("ERROR: 5.4.GroupMerger: Could not Append to texClears\n", .{});
                };
                groupData.shareIndexMap.upsert(groupLifetime.rootResource, newIndex);
            }
        }

        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.4.GroupShare: \n", .{});
            for (groupData.sharedResLifetimes.constSlice(), 0..) |sharedLifetime, i| {
                const reyTyp = getResTyp(sharedLifetime.resKey);
                const resName = switch (reyTyp) {
                    .Buf => try registryData.getBufferName(.id(sharedLifetime.resKey)),
                    .Tex => try registryData.getTextureName(.id(sharedLifetime.resKey - rc.BUF_MAX)),
                };
                std.debug.print("- {}. Shared {s} (Root {s}) (Lifetime {} -> {})\n", .{ i, @tagName(reyTyp), resName, sharedLifetime.earliest, sharedLifetime.latest });
            }
            std.debug.print("\n", .{});
            for (groupData.shareIndexMap.getConstItems(), 0..) |sharedIndex, i| {
                const resKey = groupData.shareIndexMap.getKeyByIndex(@intCast(i));
                const resTyp = getResTyp(resKey);
                const resName = switch (resTyp) {
                    .Buf => try registryData.getBufferName(.id(resKey)),
                    .Tex => try registryData.getTextureName(.id(resKey - rc.BUF_MAX)),
                };
                std.debug.print("- {}. {s} {s} -> Shared Index {}\n", .{ i, @tagName(resTyp), resName, sharedIndex });
            }
            std.debug.print("\n", .{});
        }
    }
};

fn resDescEqual(desc1: *const ResDesc, desc2: *const ResDesc) bool {
    if (std.meta.activeTag(desc1.*) != std.meta.activeTag(desc2.*)) return false;
    return switch (desc1.*) {
        .bufDesc => |desc| bufDescEqual(&desc, &desc2.bufDesc),
        .texDesc => |desc| texDescEqual(&desc, &desc2.texDesc),
    };
}

fn bufDescEqual(bufDesc1: *const BufDesc, bufDesc2: *const BufDesc) bool {
    return std.meta.eql(bufDesc1.*, bufDesc2.*);
}

fn texDescEqual(texDesc1: *const TexDesc, texDesc2: *const TexDesc) bool {
    return std.meta.eql(texDesc1.*, texDesc2.*);
}
