const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const GraphMemoryNode = @import("../renderGraph/components.zig").GraphMemoryNode;
const GraphLifetime = @import("../renderGraph/components.zig").GraphLifetime;
const SimpleIdMap = @import("../.structures/SimpleIdMap.zig").SimpleIdMap;
const LinkedIdMap = @import("../.structures/LinkedIdMap.zig").LinkedIdMap;
const DependencyData = @import("3.5_Dependency.zig").DependencyData;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const ResourceData = @import("5.5_Resource.zig").ResourceData;
const PassLoadData = @import("1_PassLoad.zig").PassLoadData;
const PassId = @import("../.configs/idConfig.zig").PassId;
const GraphData = @import("5_Graph.zig").GraphData;
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

pub const OptimizerData = struct {
    bufGraphLifetimes: LinkedIdMap(GraphLifetime, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    texGraphLifetimes: LinkedIdMap(GraphLifetime, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},
    graphMemNodes: FixedList(GraphMemoryNode, rc.PASS_MAX) = .{},
    usedBytes: SimpleIdMap(i64, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},

    optimizedGraph: SimpleIdMap(GraphMemoryNode, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{}, // Result
};

pub const OptimizerSys = struct {
    pub fn build(self: *OptimizerData, passLoad: *const PassLoadData, graph: *const GraphData, dependency: *const DependencyData, resource: *const ResourceData, registry: *const RenderRegistryData) !void {
        self.optimizedGraph.clear();

        // Skip Optimizer Stage
        if (rc.FRAME_GRAPH_SKIP_OPTIMIZE == true) {
            for (graph.graph.getConstItems()) |graphNode| {
                self.optimizedGraph.upsert(graphNode.passId, GraphMemoryNode{ .level = graphNode.level, .passId = graphNode.passId, .memWeight = 0 });
            }
            return;
        }
        // If not skipped:
        self.bufGraphLifetimes.clear();
        self.texGraphLifetimes.clear();
        self.graphMemNodes.clear();
        self.usedBytes.clear();

        for (dependency.activeBufRefs.constSlice()) |bufRef| {
            const level = graph.graph.getByKey(bufRef.passId).level;
            const bufPassId = bufRef.bufPassId;

            const bufDesc = resource.activeBufDescs.getByKey(bufPassId);
            if (bufDesc.share == .transient) {
                if (self.bufGraphLifetimes.isKeyUsed(bufPassId) == false) {
                    self.bufGraphLifetimes.insert(bufPassId, GraphLifetime{ .firstLevel = level, .lastLevel = level });
                } else {
                    var graphLifetime = self.bufGraphLifetimes.getPtrByKey(bufPassId);
                    if (level < graphLifetime.firstLevel) graphLifetime.firstLevel = level;
                    if (level > graphLifetime.lastLevel) graphLifetime.lastLevel = level;
                }
            }
        }

        for (dependency.activeTexRefs.constSlice()) |texRef| {
            const level = graph.graph.getByKey(texRef.passId).level;
            const texPassId = texRef.texPassId;

            const texDesc = resource.activeTexDescs.getByKey(texPassId);
            if (texDesc.share == .transient) {
                if (self.texGraphLifetimes.isKeyUsed(texPassId) == false) {
                    self.texGraphLifetimes.insert(texPassId, GraphLifetime{ .firstLevel = level, .lastLevel = level });
                } else {
                    var graphLifetime = self.texGraphLifetimes.getPtrByKey(texPassId);
                    if (level < graphLifetime.firstLevel) graphLifetime.firstLevel = level;
                    if (level > graphLifetime.lastLevel) graphLifetime.lastLevel = level;
                }
            }
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("6.GraphOptimizer: \n", .{});
            for (self.bufGraphLifetimes.getConstItems(), 0..) |graphLifetime, index| {
                const bufPassId = self.bufGraphLifetimes.getKeyByIndex(@intCast(index));
                const bufName = try registry.getBufferName(bufPassId);
                std.debug.print("- Buffer Graph Lifetime: (Level {} -> {}) {s} \n", .{ graphLifetime.firstLevel, graphLifetime.lastLevel, bufName });
            }
            for (self.texGraphLifetimes.getConstItems(), 0..) |graphLifetime, index| {
                const texPassId = self.texGraphLifetimes.getKeyByIndex(@intCast(index));
                const texName = try registry.getTextureName(texPassId);
                std.debug.print("- Buffer Graph Lifetime: (Level {} -> {}) {s} \n", .{ graphLifetime.firstLevel, graphLifetime.lastLevel, texName });
            }
            std.debug.print("\n", .{});
        }

        // Extend GraphNodes to GraphMemoryNodes
        for (graph.graph.getConstItems()) |graphNode| {
            const bufRange = passLoad.bufRanges.getByKey(graphNode.passId);
            const texRange = passLoad.texRanges.getByKey(graphNode.passId);

            var usedBytes: u64 = 0;
            var bornBytes: u64 = 0;
            var dyingBytes: u64 = 0;

            for (passLoad.bufRefs.constSlice()[bufRange.first..bufRange.last]) |bufRef| {
                const bufPassId = bufRef.bufPassId;
                if (self.bufGraphLifetimes.isKeyUsed(bufPassId) == true) {
                    const graphLifetime = self.bufGraphLifetimes.getByKey(bufPassId);
                    const bytes = resource.activeBufDescs.getByKey(bufPassId).guessMemoryCost();
                    usedBytes += bytes;
                    if (graphLifetime.firstLevel == graphNode.level and graphLifetime.lastLevel != graphNode.level) bornBytes += bytes;
                    if (graphLifetime.lastLevel == graphNode.level and graphLifetime.firstLevel != graphNode.level) dyingBytes += bytes;
                }
            }

            for (passLoad.texRefs.constSlice()[texRange.first..texRange.last]) |texRef| {
                const texPassId = texRef.texPassId;
                if (self.texGraphLifetimes.isKeyUsed(texPassId) == true) {
                    const graphLifetime = self.texGraphLifetimes.getByKey(texPassId);
                    const bytes = resource.activeTexDescs.getByKey(texPassId).guessMemoryCost();
                    usedBytes += bytes;
                    if (graphLifetime.firstLevel == graphNode.level and graphLifetime.lastLevel != graphNode.level) bornBytes += bytes;
                    if (graphLifetime.lastLevel == graphNode.level and graphLifetime.firstLevel != graphNode.level) dyingBytes += bytes;
                }
            }

            const castedBornBytes: i64 = @intCast(bornBytes);
            const castedDyingBytes: i64 = @intCast(dyingBytes);
            const graphMemNode = GraphMemoryNode{ .level = graphNode.level, .passId = graphNode.passId, .memWeight = castedBornBytes - castedDyingBytes };
            self.graphMemNodes.append(graphMemNode) catch std.debug.print("ERROR: 4.5.PassOptimizer: Append to graphMemNodes failed!", .{});

            const castedUsedBytes: i64 = @intCast(usedBytes);
            self.usedBytes.insert(graphNode.passId, castedUsedBytes);
        }

        // Sort first by Level then by Memory Byte Weight
        self.graphMemNodes.selectionSort(greaterGraphMemNode);

        for (self.graphMemNodes.constSlice()) |graphMemNode| {
            self.optimizedGraph.upsert(graphMemNode.passId, graphMemNode);
        }

        // Debug Output 2
        if (rc.FRAME_GRAPH_DEBUG) {
            for (self.optimizedGraph.getConstItems(), 0..) |pass, i| {
                const passName = try registry.getPassName(pass.passId);
                std.debug.print("- Nr. {}: .( .level = {}, .pass = {s}, .memWeight = {} )", .{ i, pass.level, passName, pass.memWeight });
                if (rc.FRAME_GRAPH_SKIP_OPTIMIZE == false) {
                    const usedBytes = self.usedBytes.getByKey(pass.passId);
                    std.debug.print(" (Used Bytes: {})\n", .{usedBytes});
                } else std.debug.print("\n", .{});
            }
            std.debug.print("\n", .{});
        }
    }
};

fn greaterGraphMemNode(graphMemNode1: anytype, graphMemNode2: anytype) bool {
    if (graphMemNode1.level == graphMemNode2.level) {
        if (graphMemNode1.memWeight > graphMemNode2.memWeight) return true else return false;
    }

    if (graphMemNode1.level > graphMemNode2.level) return true;
    return false;
}
