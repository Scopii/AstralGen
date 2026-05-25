const PhysicalBufLifetime = @import("../../frameBuild/components.zig").PhysicalBufLifetime;
const PhysicalTexLifetime = @import("../../frameBuild/components.zig").PhysicalTexLifetime;
const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const LifetimeMergerData = @import("../5.2_lifetimeMerger/LifetimeMergerData.zig").LifetimeMergerData;
const ResourceMapperData = @import("../5.1_resourceMapper/ResourceMapperData.zig").ResourceMapperData;
const GroupMergerData = @import("GroupMergerData.zig").GroupMergerData;

const pe = @import("../enums.zig");
const TextureEnum = pe.TextureEnum;
const BufferEnum = pe.BufferEnum;

// Step 5.4

pub const GroupMergerSys = struct {
    pub fn buildPassResources(groupMerger: *GroupMergerData, lifetimeMerger: *const LifetimeMergerData, resourceMapper: *const ResourceMapperData) void {
        // Cleanup and Prep
        groupMerger.sharedBufLifetimes.clear();
        groupMerger.sharedTexLifetimes.clear();

        groupMerger.bufShareIndexMap.clear();
        groupMerger.texShareIndexMap.clear();

        groupMerger.bufClears.clear();
        groupMerger.texClears.clear();

        // Buffer Group Sharing
        for (lifetimeMerger.transientBufGroupLifetimes.constSlice()) |groupLifetime| {
            const bufKey: u16 = @intFromEnum(groupLifetime.rootBuf);
            const bufGroup = resourceMapper.bufGroupsTransient.getByKey(bufKey); // ONLY PERSISTENT FOR TESTING!!!!!
            const bufGroupDesc = bufGroup.bufDesc;

            var candidateIndex: ?u16 = null;

            for (groupMerger.sharedBufLifetimes.slice(), 0..) |*physLifetime, index| {
                // Check if physLifetime could extend backwards
                // if (groupLifetime.latest < physLifetime.earliest) {
                //     // If it can extend check if format fits
                //     if (bufDescEqual(&bufGroupDesc, &physLifetime.bufDesc) == true) {
                //         physLifetime.earliest = groupLifetime.earliest;
                //         candidateIndex = @intCast(index);
                //         break;
                //     }
                // }

                // check if physLifetime could extend forwards
                if (physLifetime.latest < groupLifetime.earliest) {
                    // If it can extend check if format fits
                    if (bufDescEqual(&bufGroupDesc, &physLifetime.bufDesc) == true) {
                        physLifetime.latest = groupLifetime.latest;
                        candidateIndex = @intCast(index);
                        break;
                    }
                }
            }

            if (candidateIndex) |candiate| {
                // Append Clear (Might be different for backwards extension)
                groupMerger.bufClears.append(.{ .sharedBufIndex = candiate, .passAfterClear = bufGroup.rootPass }) catch {
                    std.debug.print("ERROR: 5.4.GroupMerger: Could not Append to bufClears\n", .{});
                };

                groupMerger.bufShareIndexMap.upsert(bufKey, candiate);
            } else {
                const physBufLifetime = PhysicalBufLifetime{
                    .bufDesc = bufGroupDesc,
                    .earliest = groupLifetime.earliest,
                    .latest = groupLifetime.latest,
                };

                // BLOCK WAS BEFORE (Maybe helpful for errors later!):
                // groupMerger.sharedBufLifetimes.append(physBufLifetime) catch std.debug.print("ERROR: 5.4.GroupMerger: Could not Append to sharedBufLifetimes\n", .{});
                // groupMerger.bufShareIndexMap.upsert(bufKey, @intCast(groupMerger.sharedBufLifetimes.len - 1));
                // END BEFORE

                groupMerger.sharedBufLifetimes.append(physBufLifetime) catch std.debug.print("ERROR: 5.4.GroupMerger: Could not Append to sharedBufLifetimes\n", .{});
                const newIndex: u16 = @intCast(groupMerger.sharedBufLifetimes.len - 1);

                // Append first Clear
                groupMerger.bufClears.append(.{ .sharedBufIndex = newIndex, .passAfterClear = bufGroup.rootPass }) catch {
                    std.debug.print("ERROR: 5.4.GroupMerger: Could not Append to texClears\n", .{});
                };
                groupMerger.bufShareIndexMap.upsert(bufKey, newIndex);
            }
        }

        // Texture Group Sharing
        for (lifetimeMerger.transientTexGroupLifetimes.constSlice()) |groupLifetime| {
            const texKey: u16 = @intFromEnum(groupLifetime.rootTex);
            const texGroup = resourceMapper.texGroupsTransient.getByKey(texKey); // ONLY PERSISTENT FOR TESTING!!!!!
            const texGroupDesc = texGroup.texDesc;

            var candidateIndex: ?u16 = null;

            for (groupMerger.sharedTexLifetimes.slice(), 0..) |*physLifetime, index| {
                // Check if physLifetime could extend backwards
                // if (groupLifetime.latest < physLifetime.earliest) {
                //     // If it can extend check if format fits
                //     if (texDescEqual(&texGroupDesc, &physLifetime.texDesc) == true) {
                //         physLifetime.earliest = groupLifetime.earliest;
                //         candidateIndex = @intCast(index);
                //         break;
                //     }
                // }

                // check if physLifetime could extend forwards
                if (physLifetime.latest < groupLifetime.earliest) {
                    // If it can extend check if format fits
                    if (texDescEqual(&texGroupDesc, &physLifetime.texDesc) == true) {
                        physLifetime.latest = groupLifetime.latest;
                        candidateIndex = @intCast(index);
                        break;
                    }
                }
            }

            if (candidateIndex) |candiate| {
                // Append Clear (Might be different for backwards extension)
                groupMerger.texClears.append(.{ .sharedTexIndex = candiate, .passAfterClear = texGroup.rootPass }) catch {
                    std.debug.print("ERROR: 5.4.GroupMerger: Could not Append to texClears\n", .{});
                };
                groupMerger.texShareIndexMap.upsert(texKey, candiate);
            } else {
                const physTexLifetime = PhysicalTexLifetime{
                    .texDesc = texGroupDesc,
                    .earliest = groupLifetime.earliest,
                    .latest = groupLifetime.latest,
                };

                groupMerger.sharedTexLifetimes.append(physTexLifetime) catch std.debug.print("ERROR: 5.4.GroupMerger: Could not Append to sharedTexLifetimes\n", .{});
                const newIndex: u16 = @intCast(groupMerger.sharedTexLifetimes.len - 1);

                // Append first Clear
                groupMerger.texClears.append(.{ .sharedTexIndex = newIndex, .passAfterClear = texGroup.rootPass }) catch {
                    std.debug.print("ERROR: 5.4.GroupMerger: Could not Append to texClears\n", .{});
                };
                groupMerger.texShareIndexMap.upsert(texKey, newIndex);
            }
        }

        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.4.GroupMerger: \n", .{});
            // Buffer Debug
            for (groupMerger.sharedBufLifetimes.constSlice(), 0..) |sharedLifetime, i| {
                std.debug.print("- {}. Shared Buf (Liftime {} -> {})\n", .{ i, sharedLifetime.earliest, sharedLifetime.latest });
            }
            std.debug.print("\n", .{});
            for (groupMerger.bufShareIndexMap.getConstItems(), 0..) |sharedIndex, i| {
                const castedIndex: u32 = @intCast(i);
                const bufKey = groupMerger.bufShareIndexMap.getKeyByIndex(castedIndex);
                const bufEnum: BufferEnum = @enumFromInt(bufKey);
                std.debug.print("- {}. Buf {s} -> Shared Index {}\n", .{ i, @tagName(bufEnum), sharedIndex });
            }
            std.debug.print("\n", .{});
            // Texture Debug
            for (groupMerger.sharedTexLifetimes.constSlice(), 0..) |sharedLifetime, i| {
                std.debug.print("- {}. Shared Tex (Liftime {} -> {})\n", .{ i, sharedLifetime.earliest, sharedLifetime.latest });
            }
            std.debug.print("\n", .{});
            for (groupMerger.texShareIndexMap.getConstItems(), 0..) |sharedIndex, i| {
                const castedIndex: u32 = @intCast(i);
                const texKey = groupMerger.texShareIndexMap.getKeyByIndex(castedIndex);
                const texEnum: TextureEnum = @enumFromInt(texKey);
                std.debug.print("- {}. Tex {s} -> Shared Index {}\n", .{ i, @tagName(texEnum), sharedIndex });
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
