const RenderRegistryData = @import("../../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const PhysBufLifetime = @import("../../renderGraph/components.zig").PhysBufLifetime;
const PhysTexLifetime = @import("../../renderGraph/components.zig").PhysTexLifetime;
const TextureClear = @import("../../renderGraph/components.zig").TextureClear;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const BufferClear = @import("../../renderGraph/components.zig").BufferClear;
const OptimizerData = @import("../6_Optimizer/Optimizer.zig").OptimizerData;
const LifetimeData = @import("../7_Lifetime/Lifetime.zig").LifetimeData;
const ResourceData = @import("../4_Resource/Resource.zig").ResourceData;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

pub const ShareData = struct {
    sharedBufLifetimes: FixedList(PhysBufLifetime, rc.BUF_MAX) = .{},
    sharedTexLifetimes: FixedList(PhysTexLifetime, rc.TEX_MAX) = .{},

    bufShareIndexMap: LinkedIdMap(u16, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    texShareIndexMap: LinkedIdMap(u16, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    bufClears: FixedList(BufferClear, rc.BUF_MAX) = .{},
    texClears: FixedList(TextureClear, rc.TEX_MAX) = .{},
};

pub const ShareSys = struct {
    pub fn build(self: *ShareData, resource: *const ResourceData, optimizer: *const OptimizerData, lifetime: *const LifetimeData, registry: *const RenderRegistryData) !void {
        // Cleanup and Prep
        self.sharedTexLifetimes.clear();
        self.sharedBufLifetimes.clear();
        self.texShareIndexMap.clear();
        self.bufShareIndexMap.clear();
        self.bufClears.clear();
        self.texClears.clear();

        // Buffer Share
        for (lifetime.bufLifetimes.constSlice()) |bufLifetime| {
            if (rc.FRAME_GRAPH_SKIP_SHARING == false) {
                var candidateIndex: ?u16 = null;

                for (self.sharedBufLifetimes.slice(), 0..) |*physLifetime, index| {
                    candidateIndex = @intCast(self.sharedBufLifetimes.len); // Default
                    const physDesc = resource.bufDescs.getByKey(physLifetime.bufPassId);

                    if (physLifetime.latest < bufLifetime.earliestPass) {
                        const candidateDesc = resource.bufDescs.getByKey(bufLifetime.bufPassId);

                        if (bufDescEqual(&candidateDesc, &physDesc)) {
                            physLifetime.latest = bufLifetime.latestPass;
                            candidateIndex = @intCast(index);
                            break;
                        }
                    }
                }

                if (candidateIndex) |candidate| {
                    self.bufShareIndexMap.upsert(bufLifetime.bufPassId, candidate);
                    const passAfterClear = optimizer.optimizedGraph.getConstItems()[bufLifetime.earliestPass].passId;
                    self.bufClears.append(.{ .sharedIndex = candidate, .passAfterClear = passAfterClear, .rootResource = bufLifetime.bufPassId }) catch {
                        std.debug.print("ERROR: 5.4.GroupSys: Could not Append to bufClears\n", .{});
                    };
                } else {
                    const newIndex: u16 = @intCast(self.sharedBufLifetimes.len);
                    try self.sharedBufLifetimes.append(.{ .bufPassId = bufLifetime.bufPassId, .earliest = bufLifetime.earliestPass, .latest = bufLifetime.latestPass });

                    self.bufShareIndexMap.upsert(bufLifetime.bufPassId, newIndex);
                    const passAfterClear = optimizer.optimizedGraph.getConstItems()[bufLifetime.earliestPass].passId;
                    self.bufClears.append(.{ .sharedIndex = newIndex, .passAfterClear = passAfterClear, .rootResource = bufLifetime.bufPassId }) catch {
                        std.debug.print("ERROR: 5.4.GroupSys: Could not Append to bufClears\n", .{});
                    };
                }
            }
        }

        // Texture Share
        for (lifetime.texLifetimes.constSlice()) |texLifetime| {
            if (rc.FRAME_GRAPH_SKIP_SHARING == false) {
                var candidateIndex: ?u16 = null;

                for (self.sharedTexLifetimes.slice(), 0..) |*physLifetime, index| {
                    const physDesc = resource.texDescs.getByKey(physLifetime.texPassId);

                    if (physLifetime.latest < texLifetime.earliestPass) {
                        const candidateDesc = resource.texDescs.getByKey(texLifetime.texPassId);

                        if (texDescEqual(&candidateDesc, &physDesc)) {
                            physLifetime.latest = texLifetime.latestPass;
                            candidateIndex = @intCast(index);
                            break;
                        }
                    }
                }

                if (candidateIndex) |candidate| {
                    self.texShareIndexMap.upsert(texLifetime.texPassId, candidate);
                    const passAfterClear = optimizer.optimizedGraph.getConstItems()[texLifetime.earliestPass].passId;
                    self.texClears.append(.{ .sharedIndex = candidate, .passAfterClear = passAfterClear, .rootResource = texLifetime.texPassId }) catch {
                        std.debug.print("ERROR: 5.4.GroupSys: Could not Append to bufClears\n", .{});
                    };
                } else {
                    const newIndex: u16 = @intCast(self.sharedTexLifetimes.len);
                    self.sharedTexLifetimes.append(.{ .texPassId = texLifetime.texPassId, .earliest = texLifetime.earliestPass, .latest = texLifetime.latestPass }) catch {
                        std.debug.print("ERROR: 5.4.GroupSys: Could not Append to sharedTexLifetimes\n", .{});
                    };

                    self.texShareIndexMap.upsert(texLifetime.texPassId, newIndex);
                    const passAfterClear = optimizer.optimizedGraph.getConstItems()[texLifetime.earliestPass].passId;
                    self.texClears.append(.{ .sharedIndex = newIndex, .passAfterClear = passAfterClear, .rootResource = texLifetime.texPassId }) catch {
                        std.debug.print("ERROR: 5.4.GroupSys: Could not Append to bufClears\n", .{});
                    };
                }
            }
        }

        // Debug
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("8.Share: \n", .{});

            for (self.sharedBufLifetimes.constSlice(), 0..) |sharedLifetime, i| {
                const bufName = try registry.getBufferName(sharedLifetime.bufPassId);
                std.debug.print("- {}. Shared Buf ({s}) (Lifetime {} -> {})\n", .{ i, bufName, sharedLifetime.earliest, sharedLifetime.latest });
            }
            for (self.sharedTexLifetimes.constSlice(), 0..) |sharedLifetime, i| {
                const texName = try registry.getTextureName(sharedLifetime.texPassId);
                std.debug.print("- {}. Shared Tex ({s}) (Lifetime {} -> {})\n", .{ i, texName, sharedLifetime.earliest, sharedLifetime.latest });
            }
            std.debug.print("\n", .{});

            for (self.bufShareIndexMap.getConstItems(), 0..) |sharedIndex, i| {
                const resKey = self.bufShareIndexMap.getKeyByIndex(@intCast(i));
                const resName = try registry.getBufferName(resKey);
                std.debug.print("- {}. Buf {s} -> Shared Index {}\n", .{ i, resName, sharedIndex });
            }
            for (self.texShareIndexMap.getConstItems(), 0..) |sharedIndex, i| {
                const resKey = self.texShareIndexMap.getKeyByIndex(@intCast(i));
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
