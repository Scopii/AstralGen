const PhysicalResLifetime = @import("../../renderGraph/components.zig").PhysicalResLifetime;
const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const getResTyp = @import("../../renderGraph/components.zig").getResTyp;
const resToBuf = @import("../../renderGraph/components.zig").resToBuf;
const resToTex = @import("../../renderGraph/components.zig").resToTex;

const RenderRegistryData = @import("../../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const MapperData = @import("../5.1_Mapper/MapperData.zig").MapperData;
const GroupData = @import("GroupData.zig").GroupData;

// Step 5.4

pub const GroupSys = struct {
    pub fn build(groupData: *GroupData, mapperData: *const MapperData, registry: *const RenderRegistryData) !void {
        // Cleanup and Prep
        groupData.sharedTexLifetimes.clear();
        groupData.sharedBufLifetimes.clear();
        groupData.texShareIndexMap.clear();
        groupData.bufShareIndexMap.clear();
        groupData.bufClears.clear();
        groupData.texClears.clear();

        for (mapperData.transientGroupLifetimes.constSlice()) |groupLifetime| {
            const group = mapperData.transientGroups.getByKey(groupLifetime.rootResource);

            var candidateIndex: ?u16 = null;

            switch (getResTyp(groupLifetime.rootResource)) {
                .Buf => {
                    if (rc.FRAME_GRAPH_SKIP_SHARING == false) {
                        for (groupData.sharedBufLifetimes.slice(), 0..) |*physLifetime, index| {
                            const physDesc = mapperData.transientGroups.getByKey(physLifetime.resKey).desc.bufDesc;

                            if (physLifetime.latest < groupLifetime.earliestPass) {
                                if (bufDescEqual(&group.desc.bufDesc, &physDesc)) {
                                    physLifetime.latest = groupLifetime.latestPass;
                                    candidateIndex = @intCast(index);
                                    break;
                                }
                            }
                        }
                    }

                    if (candidateIndex) |candidate| {
                        groupData.bufShareIndexMap.upsert(resToBuf(groupLifetime.rootResource), candidate);
                        groupData.bufClears.append(.{ .sharedIndex = candidate, .passAfterClear = group.rootPass, .rootResource = resToBuf(groupLifetime.rootResource) }) catch {
                            std.debug.print("ERROR: 5.4.GroupSys: Could not Append to bufClears\n", .{});
                        };
                    } else {
                        groupData.sharedBufLifetimes.append(.{ .resKey = groupLifetime.rootResource, .earliest = groupLifetime.earliestPass, .latest = groupLifetime.latestPass }) catch {
                            std.debug.print("ERROR: 5.4.GroupSys: Could not Append to sharedBufLifetimes\n", .{});
                        };
                        const newIndex: u16 = @intCast(groupData.sharedBufLifetimes.len - 1);

                        groupData.bufShareIndexMap.upsert(resToBuf(groupLifetime.rootResource), newIndex);
                        groupData.bufClears.append(.{ .sharedIndex = newIndex, .passAfterClear = group.rootPass, .rootResource = resToBuf(groupLifetime.rootResource) }) catch {
                            std.debug.print("ERROR: 5.4.GroupSys: Could not Append to bufClears\n", .{});
                        };
                    }
                },
                .Tex => {
                    if (rc.FRAME_GRAPH_SKIP_SHARING == false) {
                        for (groupData.sharedTexLifetimes.slice(), 0..) |*physLifetime, index| {
                            const physDesc = mapperData.transientGroups.getByKey(physLifetime.resKey).desc.texDesc;

                            if (physLifetime.latest < groupLifetime.earliestPass) {
                                if (texDescEqual(&group.desc.texDesc, &physDesc)) {
                                    physLifetime.latest = groupLifetime.latestPass;
                                    candidateIndex = @intCast(index);
                                    break;
                                }
                            }
                        }
                    }

                    if (candidateIndex) |candidate| {
                        groupData.texShareIndexMap.upsert(resToTex(groupLifetime.rootResource), candidate);
                        groupData.texClears.append(.{ .sharedIndex = candidate, .passAfterClear = group.rootPass, .rootResource = resToTex(groupLifetime.rootResource) }) catch {
                            std.debug.print("ERROR: 5.4.GroupSys: Could not Append to texClears\n", .{});
                        };
                    } else {
                        groupData.sharedTexLifetimes.append(.{ .resKey = groupLifetime.rootResource, .earliest = groupLifetime.earliestPass, .latest = groupLifetime.latestPass }) catch {
                            std.debug.print("ERROR: 5.4.GroupSys: Could not Append to sharedTexLifetimes\n", .{});
                        };
                        const newIndex: u16 = @intCast(groupData.sharedTexLifetimes.len - 1);

                        groupData.texShareIndexMap.upsert(resToTex(groupLifetime.rootResource), newIndex);
                        groupData.texClears.append(.{ .sharedIndex = newIndex, .passAfterClear = group.rootPass, .rootResource = resToTex(groupLifetime.rootResource) }) catch {
                            std.debug.print("ERROR: 5.4.GroupSys: Could not Append to texClears\n", .{});
                        };
                    }
                },
            }
        }

        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.4.GroupShare: \n", .{});

            for (groupData.sharedBufLifetimes.constSlice(), 0..) |sharedLifetime, i| {
                const resName = try registry.getResourceName(sharedLifetime.resKey);
                std.debug.print("- {}. Shared Buf (Root {s}) (Lifetime {} -> {})\n", .{ i, resName, sharedLifetime.earliest, sharedLifetime.latest });
            }
            for (groupData.sharedTexLifetimes.constSlice(), 0..) |sharedLifetime, i| {
                const resName = try registry.getResourceName(sharedLifetime.resKey);
                std.debug.print("- {}. Shared Tex (Root {s}) (Lifetime {} -> {})\n", .{ i, resName, sharedLifetime.earliest, sharedLifetime.latest });
            }
            std.debug.print("\n", .{});

            for (groupData.bufShareIndexMap.getConstItems(), 0..) |sharedIndex, i| {
                const resKey = groupData.bufShareIndexMap.getKeyByIndex(@intCast(i));
                const resName = try registry.getBufferName(resKey);
                std.debug.print("- {}. Buf {s} -> Shared Index {}\n", .{ i, resName, sharedIndex });
            }
            for (groupData.texShareIndexMap.getConstItems(), 0..) |sharedIndex, i| {
                const resKey = groupData.texShareIndexMap.getKeyByIndex(@intCast(i));
                const resName = try registry.getTextureName(resKey);
                std.debug.print("- {}. Tex {s} -> Shared Index {}\n", .{ i, resName, sharedIndex });
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
