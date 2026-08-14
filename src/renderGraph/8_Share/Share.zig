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
                const newDesc = resource.bufDescs.getByKey(bufLifetime.bufPassId);

                for (self.sharedBufLifetimes.slice(), 0..) |*physLifetime, index| {
                    const candidateDesc = physLifetime.bufDesc;

                    if (physLifetime.latest < bufLifetime.earliestPass) {
                        if (bufDescEqual(&newDesc, &candidateDesc)) {
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

                    try self.sharedBufLifetimes.append(.{ .earliest = bufLifetime.earliestPass, .latest = bufLifetime.latestPass, .bufDesc = newDesc });

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
                const newDesc = resource.texDescs.getByKey(texLifetime.texPassId);

                for (self.sharedTexLifetimes.slice(), 0..) |*physLifetime, index| {
                    const candidateDesc = physLifetime.texDesc;

                    if (physLifetime.latest < texLifetime.earliestPass) {
                        if (tryCompatibleTexDesc(&newDesc, &candidateDesc)) |compatibleTexDesc| {
                            physLifetime.latest = texLifetime.latestPass;
                            physLifetime.texDesc = compatibleTexDesc;
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

                    try self.sharedTexLifetimes.append(.{ .earliest = texLifetime.earliestPass, .latest = texLifetime.latestPass, .texDesc = newDesc });

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
                std.debug.print("- {}. Shared Buf (Lifetime {} -> {})\n", .{ i, sharedLifetime.earliest, sharedLifetime.latest });
            }
            for (self.sharedTexLifetimes.constSlice(), 0..) |sharedLifetime, i| {
                std.debug.print("- {}. Shared Tex (Lifetime {} -> {})\n", .{ i, sharedLifetime.earliest, sharedLifetime.latest });
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

// fn tryCompatibleTexDesc(texDesc1: *const TexDesc, texDesc2: *const TexDesc) ?TexDesc {
//     return if (std.meta.eql(texDesc1.*, texDesc2.*) == true) texDesc1.* else null;
// }

fn tryCompatibleTexDesc(texDesc1: *const TexDesc, texDesc2: *const TexDesc) ?TexDesc {
    const compatible =
        if (texDesc1.share == texDesc2.share and
        texDesc1.mem == texDesc2.mem and
        texDesc1.typ == texDesc2.typ and
        texDesc1.width == texDesc2.width and
        texDesc1.height == texDesc2.height and
        texDesc1.depth == texDesc2.depth and
        texDesc1.update == texDesc2.update and
        // texDesc1.fitPass == texDesc2.fitPass
        texDesc1.resize == .Block and texDesc2.resize == .Block) true else false;

    if (rc.FRAME_GRAPH_AGGRESSIVE_TEXTURE_SHARE == true and compatible == true) {
        return TexDesc{
            .share = texDesc1.share, // Only used by graph
            .mem = texDesc1.mem,
            .typ = texDesc1.typ,
            .width = texDesc1.width,
            .height = texDesc1.height,
            .depth = texDesc1.depth,
            .update = texDesc1.update,
            .fitPass = texDesc1.fitPass, // Only used by graph
            .resize = .Block,
            .descriptors = if (texDesc1.descriptors == .StorageSampled or
                texDesc2.descriptors == .StorageSampled or
                texDesc1.descriptors != texDesc2.descriptors) .StorageSampled else texDesc1.descriptors,

            .texUse = .{
                .colorAtt = if (texDesc1.texUse.colorAtt | texDesc2.texUse.colorAtt) true else false,
                .depthAtt = if (texDesc1.texUse.depthAtt | texDesc2.texUse.depthAtt) true else false,
                .storage = if (texDesc1.texUse.storage | texDesc2.texUse.storage) true else false,
                .sampled = if (texDesc1.texUse.sampled | texDesc2.texUse.sampled) true else false,
                .transferSrc = if (texDesc1.texUse.transferSrc | texDesc2.texUse.transferSrc) true else false,
                .transferDst = if (texDesc1.texUse.transferDst | texDesc2.texUse.transferDst) true else false,
            },
        };
    }

    if (texDesc1.descriptors == texDesc2.descriptors and std.meta.eql(texDesc1.texUse, texDesc2.texUse) and compatible) {
        return TexDesc{
            .share = texDesc1.share, // Only used by graph
            .mem = texDesc1.mem,
            .typ = texDesc1.typ,
            .width = texDesc1.width,
            .height = texDesc1.height,
            .depth = texDesc1.depth,
            .update = texDesc1.update,
            .fitPass = texDesc1.fitPass, // Only used by graph
            .descriptors = texDesc1.descriptors,
            .resize = .Block,
            .texUse = texDesc1.texUse,
        };
    }

    return null;
}
