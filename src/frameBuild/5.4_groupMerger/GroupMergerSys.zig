const PhysicalBufLifetime = @import("../../frameBuild/components.zig").PhysicalBufLifetime;
const PhysicalTexLifetime = @import("../../frameBuild/components.zig").PhysicalTexLifetime;
const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const ResourceRegistryData = @import("../0_resourceRegistry/ResourceRegistryData.zig").ResourceRegistryData;
const ResourceExtractorData = @import("../2_resourceExtractor/ResourceExtractorData.zig").ResourceExtractorData;
const ResourceMapperData = @import("../5.1_resourceMapper/ResourceMapperData.zig").ResourceMapperData;
const LifetimeMergerData = @import("../5.2_lifetimeMerger/LifetimeMergerData.zig").LifetimeMergerData;
const GroupMergerData = @import("GroupMergerData.zig").GroupMergerData;


// Step 5.4

pub const GroupMergerSys = struct {
    pub fn buildPassResources(
        groupMerger: *GroupMergerData,
        resourceExtractor: *ResourceExtractorData,
        lifetimeMerger: *const LifetimeMergerData,
        resourceMapper: *const ResourceMapperData,
        resourceRegistry: *const ResourceRegistryData,
    ) !void {
        // Cleanup and Prep
        groupMerger.sharedBufLifetimes.clear();
        groupMerger.sharedTexLifetimes.clear();

        groupMerger.bufShareIndexMap.clear();
        groupMerger.texShareIndexMap.clear();

        groupMerger.bufClears.clear();
        groupMerger.texClears.clear();

        // Buffer Group Sharing
        for (lifetimeMerger.transientBufGroupLifetimes.constSlice()) |groupLifetime| {
            const bufGroupKey: u16 = groupLifetime.rootBuf.val();
            const bufGroup = resourceMapper.bufGroupsTransient.getByKey(bufGroupKey);
            const bufGroupDesc = resourceExtractor.bufDescriptions.getByKey(bufGroupKey);

            var candidateIndex: ?u16 = null;

            for (groupMerger.sharedBufLifetimes.slice(), 0..) |*physLifetime, index| {
                const physLifetimeDesc = resourceExtractor.bufDescriptions.getByKey(physLifetime.bufDescId.val());

                // check if physLifetime could extend forwards
                if (physLifetime.latest < groupLifetime.earliest) {
                    // If it can extend check if format fits
                    if (bufDescEqual(&bufGroupDesc, &physLifetimeDesc) == true) {
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

                groupMerger.bufShareIndexMap.upsert(bufGroupKey, candiate);
            } else {
                const physBufLifetime = PhysicalBufLifetime{
                    .bufDescId = groupLifetime.rootBuf,
                    .earliest = groupLifetime.earliest,
                    .latest = groupLifetime.latest,
                };

                groupMerger.sharedBufLifetimes.append(physBufLifetime) catch std.debug.print("ERROR: 5.4.GroupMerger: Could not Append to sharedBufLifetimes\n", .{});
                const newIndex: u16 = @intCast(groupMerger.sharedBufLifetimes.len - 1);

                // Append first Clear
                groupMerger.bufClears.append(.{ .sharedBufIndex = newIndex, .passAfterClear = bufGroup.rootPass }) catch {
                    std.debug.print("ERROR: 5.4.GroupMerger: Could not Append to texClears\n", .{});
                };
                groupMerger.bufShareIndexMap.upsert(bufGroupKey, newIndex);
            }
        }

        // Texture Group Sharing
        for (lifetimeMerger.transientTexGroupLifetimes.constSlice()) |groupLifetime| {
            const texGroupKey: u16 = groupLifetime.rootTex.val();
            const texGroup = resourceMapper.texGroupsTransient.getByKey(texGroupKey);
            const texGroupDesc = resourceExtractor.texDescriptions.getByKey(texGroupKey);

            var candidateIndex: ?u16 = null;

            for (groupMerger.sharedTexLifetimes.slice(), 0..) |*physLifetime, index| {
                const physLifetimeDesc = resourceExtractor.texDescriptions.getByKey(physLifetime.texDescId.val());

                // check if physLifetime could extend forwards
                if (physLifetime.latest < groupLifetime.earliest) {
                    // If it can extend check if format fits
                    if (texDescEqual(&texGroupDesc, &physLifetimeDesc) == true) {
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
                groupMerger.texShareIndexMap.upsert(texGroupKey, candiate);
            } else {
                const physTexLifetime = PhysicalTexLifetime{
                    .texDescId = groupLifetime.rootTex,
                    .earliest = groupLifetime.earliest,
                    .latest = groupLifetime.latest,
                };

                groupMerger.sharedTexLifetimes.append(physTexLifetime) catch std.debug.print("ERROR: 5.4.GroupMerger: Could not Append to sharedTexLifetimes\n", .{});
                const newIndex: u16 = @intCast(groupMerger.sharedTexLifetimes.len - 1);

                // Append first Clear
                groupMerger.texClears.append(.{ .sharedTexIndex = newIndex, .passAfterClear = texGroup.rootPass }) catch {
                    std.debug.print("ERROR: 5.4.GroupMerger: Could not Append to texClears\n", .{});
                };
                groupMerger.texShareIndexMap.upsert(texGroupKey, newIndex);
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
                const bufKey = groupMerger.bufShareIndexMap.getKeyByIndex(@intCast(i));
                const bufName = try resourceRegistry.getBufferName(.id(bufKey));
                std.debug.print("- {}. Buf {s} -> Shared Index {}\n", .{ i, bufName, sharedIndex });
            }
            std.debug.print("\n", .{});
            // Texture Debug
            for (groupMerger.sharedTexLifetimes.constSlice(), 0..) |sharedLifetime, i| {
                std.debug.print("- {}. Shared Tex (Liftime {} -> {})\n", .{ i, sharedLifetime.earliest, sharedLifetime.latest });
            }
            std.debug.print("\n", .{});
            for (groupMerger.texShareIndexMap.getConstItems(), 0..) |sharedIndex, i| {
                const texKey = groupMerger.texShareIndexMap.getKeyByIndex(@intCast(i));
                const texName = try resourceRegistry.getTextureName(.id(texKey));
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
