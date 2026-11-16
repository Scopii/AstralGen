const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const PhysTexLifetime = @import("../renderGraph/components.zig").SharedTexture;
const PhysBufLifetime = @import("../renderGraph/components.zig").SharedBuffer;
const PassRefRange = @import("../renderGraph/components.zig").PassRefRange;
const LinkedIdMap = @import("../.structures/LinkedIdMap.zig").LinkedIdMap;
const SimpleIdMap = @import("../.structures/SimpleIdMap.zig").SimpleIdMap;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const TexDesc = @import("../render/types/res/Texture.zig").TexDesc;
const BufDesc = @import("../render/types/res/Buffer.zig").BufDesc;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const OptimizerData = @import("6_Optimizer.zig").OptimizerData;
const ResourceData = @import("5.5_Resource.zig").ResourceData;
const LifetimeData = @import("7_Lifetime.zig").LifetimeData;
const PassId = @import("../.configs/idConfig.zig").PassId;
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

pub const ShareData = struct {
    sharedBuffers: FixedList(PhysBufLifetime, rc.BUF_MAX) = .{},
    sharedTextures: FixedList(PhysTexLifetime, rc.TEX_MAX) = .{},

    bufShareIndices: LinkedIdMap(u16, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    texShareIndices: LinkedIdMap(u16, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    bufClearIndices: LinkedIdMap(PassRefRange, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
    bufClears: FixedList(struct { bufPassId: BufPassId, passPosition: u16 }, rc.BUF_MAX) = .{},

    texClearIndices: LinkedIdMap(PassRefRange, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
    texClearCmds: FixedList(struct { texPassId: TexPassId, passPosition: u16 }, rc.TEX_MAX) = .{},
    texClearPasses: LinkedIdMap(PassId, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},
};

pub const ShareSys = struct {
    pub fn build(self: *ShareData, resource: *const ResourceData, optimizer: *const OptimizerData, lifetime: *const LifetimeData, registry: *const RenderRegistryData, debug: bool) !void {
        // Cleanup and Prep
        self.sharedTextures.clear();
        self.sharedBuffers.clear();

        self.texShareIndices.clear();
        self.bufShareIndices.clear();

        self.bufClearIndices.clear();
        self.bufClears.clear();

        self.texClearIndices.clear();
        self.texClearPasses.clear();
        self.texClearCmds.clear();

        // Building Buf Clears (Based on Lifetimes being Sorted)
        for (lifetime.bufLifetimes.constSlice()) |bufLifetime| {
            try self.bufClears.append(.{ .bufPassId = bufLifetime.bufPassId, .passPosition = bufLifetime.earliest });

            const passId = optimizer.optimizedGraph.getConstItems()[bufLifetime.earliest].passId;

            if (self.bufClearIndices.isKeyUsed(passId) == false) {
                self.bufClearIndices.insert(passId, .{ .first = @intCast(self.bufClears.len - 1), .last = @intCast(self.bufClears.len) });
            } else self.bufClearIndices.getPtrByKey(passId).last = @intCast(self.bufClears.len);
        }

        // Building Tex Clears (Based on Lifetimes being Sorted)
        for (lifetime.texLifetimes.constSlice()) |texLifetime| {
            const passId = optimizer.optimizedGraph.getConstItems()[texLifetime.earliest].passId;
            self.texClearPasses.insert(texLifetime.texPassId, passId); // for pass OP_LOAD clear

            if (texLifetime.firstUseIsAttachment == false) {
                try self.texClearCmds.append(.{ .texPassId = texLifetime.texPassId, .passPosition = texLifetime.earliest });

                if (self.texClearIndices.isKeyUsed(passId) == false) {
                    self.texClearIndices.insert(passId, .{ .first = @intCast(self.texClearCmds.len - 1), .last = @intCast(self.texClearCmds.len) });
                } else self.texClearIndices.getPtrByKey(passId).last = @intCast(self.texClearCmds.len);
            }
        }

        // Buffer Share
        const bufLifetimes = if (rc.FRAME_GRAPH_USE_GRAPH_LEVEL_LIFETIMES) optimizer.bufGraphLifetimes.getConstItems() else lifetime.bufLifetimes.constSlice();

        for (bufLifetimes, 0..) |bufLifetime, bufIndex| {
            var candidateIndex: ?u16 = null;
            const bufPassId = if (rc.FRAME_GRAPH_USE_GRAPH_LEVEL_LIFETIMES) optimizer.bufGraphLifetimes.getKeyByIndex(@intCast(bufIndex)) else bufLifetime.bufPassId;
            const newDesc = resource.activeBufDescs.getByKey(bufPassId);

            if (rc.FRAME_GRAPH_SKIP_SHARING == false) {
                for (self.sharedBuffers.slice(), 0..) |*physLifetime, index| {
                    const candidateDesc = physLifetime.bufDesc;

                    if (physLifetime.latest < bufLifetime.earliest) {
                        if (bufDescEqual(&newDesc, &candidateDesc)) {
                            physLifetime.latest = bufLifetime.latest;
                            candidateIndex = @intCast(index);
                            break;
                        }
                    }
                }
            }

            if (candidateIndex) |candidate| {
                self.bufShareIndices.upsert(bufPassId, candidate);
            } else {
                const newIndex: u16 = @intCast(self.sharedBuffers.len);
                try self.sharedBuffers.append(.{ .earliest = bufLifetime.earliest, .latest = bufLifetime.latest, .bufDesc = newDesc });
                self.bufShareIndices.upsert(bufPassId, newIndex);
            }
        }

        const texLifetimes = if (rc.FRAME_GRAPH_USE_GRAPH_LEVEL_LIFETIMES) optimizer.texGraphLifetimes.getConstItems() else lifetime.texLifetimes.constSlice();

        // Texture Share
        for (texLifetimes, 0..) |texLifetime, texIndex| {
            var candidateIndex: ?u16 = null;
            const texPassId = if (rc.FRAME_GRAPH_USE_GRAPH_LEVEL_LIFETIMES) optimizer.texGraphLifetimes.getKeyByIndex(@intCast(texIndex)) else texLifetime.texPassId;
            const newDesc = resource.activeTexDescs.getByKey(texPassId);

            if (rc.FRAME_GRAPH_SKIP_SHARING == false) {
                for (self.sharedTextures.slice(), 0..) |*physLifetime, index| {
                    const candidateDesc = physLifetime.texDesc;

                    if (physLifetime.latest < texLifetime.earliest) {
                        if (tryCompatibleTexDesc(&newDesc, &candidateDesc)) |compatibleTexDesc| {
                            physLifetime.latest = texLifetime.latest;
                            physLifetime.texDesc = compatibleTexDesc;
                            candidateIndex = @intCast(index);
                            break;
                        }
                    }
                }
            }

            if (candidateIndex) |candidate| {
                self.texShareIndices.upsert(texPassId, candidate);
            } else {
                const newIndex: u16 = @intCast(self.sharedTextures.len);
                try self.sharedTextures.append(.{ .earliest = texLifetime.earliest, .latest = texLifetime.latest, .texDesc = newDesc });
                self.texShareIndices.upsert(texPassId, newIndex);
            }
        }

        // Debug
        if (debug) {
            std.debug.print("8.Share: \n", .{});

            var totalMemEstimate: u64 = 0;

            for (self.sharedBuffers.constSlice(), 0..) |sharedLifetime, i| {
                const memEstimate = sharedLifetime.bufDesc.guessMemoryCost();
                totalMemEstimate += memEstimate;
                std.debug.print("- {}. Shared Buf (Lifetime {} -> {}) (Memory: {} bytes)\n", .{ i, sharedLifetime.earliest, sharedLifetime.latest, memEstimate });
            }
            for (self.sharedTextures.constSlice(), 0..) |sharedLifetime, i| {
                const memEstimate = sharedLifetime.texDesc.guessMemoryCost();
                totalMemEstimate += memEstimate;
                std.debug.print("- {}. Shared Tex (Lifetime {} -> {}) (Memory: {} bytes)\n", .{ i, sharedLifetime.earliest, sharedLifetime.latest, memEstimate });
            }
            std.debug.print("Total Memory Estimate: {} bytes\n\n", .{totalMemEstimate});

            for (self.bufShareIndices.getConstItems(), 0..) |sharedIndex, i| {
                const resKey = self.bufShareIndices.getKeyByIndex(@intCast(i));
                const resName = try registry.getBufferName(resKey);
                std.debug.print("- {}. Buf {s} -> Shared Index {}\n", .{ i, resName, sharedIndex });
            }
            for (self.texShareIndices.getConstItems(), 0..) |sharedIndex, i| {
                const resKey = self.texShareIndices.getKeyByIndex(@intCast(i));
                const resName = try registry.getTextureName(resKey);
                std.debug.print("- {}. Tex {s} -> Shared Index {}\n", .{ i, resName, sharedIndex });
            }
            std.debug.print("\n", .{});

            for (self.bufClearIndices.getConstItems()) |bufClearIndices| {
                for (self.bufClears.constSlice()[bufClearIndices.first..bufClearIndices.last]) |bufClear| {
                    const bufName = try registry.getBufferName(bufClear.bufPassId);
                    const passId = optimizer.optimizedGraph.getConstItems()[bufClear.passPosition].passId;
                    const passName = try registry.getPassName(passId);
                    std.debug.print("- Pass {s} clears {s} (Buf)\n", .{ passName, bufName });
                }
            }

            for (self.texClearIndices.getConstItems()) |texClearIndices| {
                for (self.texClearCmds.constSlice()[texClearIndices.first..texClearIndices.last]) |texClear| {
                    const texName = try registry.getTextureName(texClear.texPassId);
                    const passId = optimizer.optimizedGraph.getConstItems()[texClear.passPosition].passId;
                    const passName = try registry.getPassName(passId);
                    std.debug.print("- Pass {s} clears {s} (Tex)\n", .{ passName, texName });
                }
                std.debug.print("\n", .{});
            }

            for (self.texClearPasses.getConstItems(), 0..) |texClearPass, i| {
                const texPassId = self.texClearPasses.getKeyByIndex(@intCast(i));
                const texName = try registry.getTextureName(texPassId);
                const passName = try registry.getPassName(texClearPass);
                std.debug.print("- Pass {s} clears {s} (Tex) with LOAD_OP\n", .{ passName, texName });
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
