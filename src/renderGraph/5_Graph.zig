const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const ResourceVersion = @import("../renderGraph/components.zig").ResourceVersion;
const SimpleIdMap = @import("../.structures/SimpleIdMap.zig").SimpleIdMap;
const LinkedIdMap = @import("../.structures/LinkedIdMap.zig").LinkedIdMap;
const GraphNode = @import("../renderGraph/components.zig").GraphNode;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const DependencyData = @import("3.5_Dependency.zig").DependencyData;
const OutputLoadData = @import("2_OutputLoad.zig").OutputLoadData;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const ResourceData = @import("5.5_Resource.zig").ResourceData;
const PassLoadData = @import("1_PassLoad.zig").PassLoadData;
const PassId = @import("../.configs/idConfig.zig").PassId;
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

pub const GraphData = struct {
    passDepCounters: LinkedIdMap(u16, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
    readyPasses: FixedList(GraphNode, rc.PASS_MAX) = .{},
    graph: SimpleIdMap(GraphNode, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},

    texVersions: SimpleIdMap(ResourceVersion, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},
    bufVersions: SimpleIdMap(ResourceVersion, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
};

pub const GraphSys = struct {
    pub fn build(self: *GraphData, passLoad: *const PassLoadData, outputLoad: *const OutputLoadData, dependency: *const DependencyData, registry: *const RenderRegistryData) !void {
        self.passDepCounters.clear();
        self.graph.clear();
        self.readyPasses.clear();

        self.texVersions.clear();
        self.bufVersions.clear();

        // Fill Passes with Buffer Dependancy Count
        for (dependency.dependencies.constSlice()) |dep| {
            const curDepCount = if (self.passDepCounters.isKeyUsed(dep.successor)) self.passDepCounters.getByKey(dep.successor) else 0;
            self.passDepCounters.upsert(dep.successor, curDepCount + 1);
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.GraphExtractor: \n", .{});
            for (0..self.passDepCounters.getLength()) |i| {
                const passDepCount = self.passDepCounters.getByIndex(@intCast(i));
                const passId = self.passDepCounters.getKeyByIndex(@intCast(i));
                const passName = try registry.getPassName(passId);
                std.debug.print("- Pass {s}: Dependancies {}\n", .{ passName, passDepCount });
            }
            std.debug.print("\n", .{});
        }

        // Add all Passes that do not have Dependancys
        for (outputLoad.activePasses.getConstItems()) |pass| {
            if (self.passDepCounters.isKeyUsed(pass) == false) {
                self.readyPasses.appendAssumeCapacity(.{ .passId = pass, .level = 0 });
            }
        }

        // Single Queue Topological Sort
        var readIndex: u32 = 0;

        while (readIndex < self.readyPasses.len) {
            // Read current pass and advance index
            const pass = self.readyPasses.buffer[readIndex];
            readIndex += 1;
            // Place into ordered passes
            self.graph.upsert(pass.passId, pass);
            // Calc level for any children
            const nextLevel = pass.level + 1;

            // Decrement Buffer Dependencies
            for (dependency.dependencies.constSlice()) |dep| {
                if (dep.predecessor == pass.passId) {
                    const ptr = self.passDepCounters.getPtrByKey(dep.successor);
                    ptr.* -= 1;
                    // Queue to END of current list if its 0
                    if (ptr.* == 0) self.readyPasses.appendAssumeCapacity(GraphNode{ .passId = dep.successor, .level = nextLevel });
                }
            }
        }

        // Graph Validation Check
        const orderedCount = self.graph.getLength();
        const totalCount = outputLoad.activePasses.getLength();

        if (orderedCount != totalCount) {
            std.debug.print("ERROR: 4.0.GraphExtractor: {} of {} passes scheduled! Graph has a cycle\n", .{ orderedCount, totalCount });
            // Passes in unorderedPasses but not in orderedPasses
            for (outputLoad.activePasses.getConstItems()) |passId| {
                if (self.graph.isKeyUsed(passId) == false) {
                    const openDeps = if (self.passDepCounters.isKeyUsed(passId)) self.passDepCounters.getByKey(passId) else 0;
                    const passString = try registry.getPassName(passId);
                    std.debug.print("  stuck: {s} (still waiting on {} deps)\n", .{ passString, openDeps });
                }
            }
            for (dependency.dependencies.constSlice()) |dep| {
                const predStuck = !self.graph.isKeyUsed(dep.predecessor);
                const succStuck = !self.graph.isKeyUsed(dep.successor);

                if (predStuck and succStuck) {
                    const predName = try registry.getPassName(dep.predecessor);
                    const succName = try registry.getPassName(dep.successor);
                    std.debug.print("    {s} -- --> {s}\n", .{ predName, succName });
                }
            }
            return error.GraphHasCycle;
        }

        // Texture Version Validation (every ref must use the latest version of its resource)
        for (self.graph.getConstItems()) |graphNode| {
            const texRange = passLoad.texRanges.getByKey(graphNode.passId);
            for (passLoad.texRefs.constSlice()[texRange.first..texRange.last]) |texRef| {
                if (self.texVersions.isKeyUsed(texRef.texPassId) == false) self.texVersions.insert(texRef.texPassId, .{});
                const texVersion = self.texVersions.getPtrByKey(texRef.texPassId);

                const usesLatest = texRef.rootPassId == texVersion.latestWriter;
                if (usesLatest == false or (texRef.access == .write and texVersion.latestIsRead)) {
                    const texName = try registry.getTextureName(texRef.texPassId);
                    const passName = try registry.getPassName(texRef.passId);
                    std.debug.print("ERROR: 5.Graph: {s} uses Tex ({s}) but was already written over, already read (for a write), or from-pass doesnt write it\n", .{ passName, texName });
                    return error.TextureVersionConflict;
                }

                // Transient textures have no contents before the frame -> reading the start version reads nothing anyone wrote
                if (texRef.access == .read and texRef.rootPassId == null and (try registry.getTextureDefinition(texRef.texPassId)).share == .transient) {
                    const texName = try registry.getTextureName(texRef.texPassId);
                    const passName = try registry.getPassName(texRef.passId);
                    std.debug.print("ERROR: 5.Graph: {s} reads transient Texture {s} without a from (nothing wrote it this frame)\n", .{ passName, texName });
                    return error.TransientReadBeforeWrite;
                }

                if (texRef.access == .write) {
                    texVersion.latestWriter = texRef.passId; // pass now holds the newest version
                    texVersion.latestIsRead = false;
                } else texVersion.latestIsRead = true;
            }
        }

        // Buffer Version Validation (every ref must use the latest version of its resource)
        for (self.graph.getConstItems()) |graphNode| {
            const bufRange = passLoad.bufRanges.getByKey(graphNode.passId);
            for (passLoad.bufRefs.constSlice()[bufRange.first..bufRange.last]) |bufRef| {
                if (self.bufVersions.isKeyUsed(bufRef.bufPassId) == false) self.bufVersions.insert(bufRef.bufPassId, .{});
                const bufVersion = self.bufVersions.getPtrByKey(bufRef.bufPassId);

                const usesLatest = bufRef.rootPassId == bufVersion.latestWriter;
                if (usesLatest == false or (bufRef.access == .write and bufVersion.latestIsRead)) {
                    const bufName = try registry.getBufferName(bufRef.bufPassId);
                    const passName = try registry.getPassName(bufRef.passId);
                    std.debug.print("ERROR: 5.Graph: {s} uses Buf ({s}) but was already written over, already read (for a write), or from-pass doesnt write it\n", .{ passName, bufName });
                    return error.BufferVersionConflict;
                }

                // Transient buffers have no contents before the frame -> reading the start version reads nothing anyone wrote
                if (bufRef.access == .read and bufRef.rootPassId == null and (try registry.getBufferDefinition(bufRef.bufPassId)).share == .transient) {
                    const bufName = try registry.getBufferName(bufRef.bufPassId);
                    const passName = try registry.getPassName(bufRef.passId);
                    std.debug.print("ERROR: 5.Graph: {s} reads transient Buffer {s} without a from (nothing wrote it this frame)\n", .{ passName, bufName });
                    return error.TransientReadBeforeWrite;
                }

                if (bufRef.access == .write) {
                    bufVersion.latestWriter = bufRef.passId; // pass now holds the newest version
                    bufVersion.latestIsRead = false;
                } else bufVersion.latestIsRead = true;
            }
        }

        // Debug
        if (rc.FRAME_GRAPH_DEBUG) {
            for (self.graph.getConstItems(), 0..) |pass, i| {
                const passName = try registry.getPassName(pass.passId);
                std.debug.print("- Nr. {}: .( .level = {}, .pass = {s})\n", .{ i, pass.level, passName });
            }
            std.debug.print("\n", .{});
        }
    }
};
