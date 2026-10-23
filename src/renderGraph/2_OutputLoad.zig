const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const SimpleIdMap = @import("../.structures/SimpleIdMap.zig").SimpleIdMap;
const ViewportData = @import("../viewport/ViewportData.zig").ViewportData;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const PassLoadData = @import("1_PassLoad.zig").PassLoadData;
const PassId = @import("../.configs/idConfig.zig").PassId;
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

pub const OutputLoadData = struct {
    pendingPasses: FixedList(PassId, rc.PASS_MAX) = .{},
    activePasses: SimpleIdMap(PassId, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
};

pub const OutputLoadSys = struct {
    pub fn build(self: *OutputLoadData, passLoad: *const PassLoadData, registry: *const RenderRegistryData, viewportData: *const ViewportData, manuelPasses: []const PassId) !void {
        self.pendingPasses.clear();
        self.activePasses.clear();

        // Load Producing Passes of Each Viewports Output
        for (viewportData.activeViewportIds.getConstItems()) |viewportId| {
            const viewport = viewportData.viewports.getByKey(viewportId.val());

            for (viewport.outputTuples) |outputTuple| {
                const passId = try registry.getPassId(outputTuple.passName);
                const texPassId = try registry.getTexturePassId(outputTuple.texName);

                // Check if Range Exists
                if (passLoad.texRanges.isKeyUsed(passId) == false) {
                    std.debug.print("ERROR in OutputLoadSys: Viewport Output PassId has no Range!\n", .{});
                    return error.OutputTupleNoRange;
                }

                // Check if Pass Range Contains Texture
                const texRange = passLoad.texRanges.getByKey(passId);
                const refRange = passLoad.texRefs.constSlice()[texRange.first..texRange.last];

                var foundTex = false;

                for (refRange) |texRef| {
                    if (texPassId == texRef.texPassId) {
                        if (self.activePasses.isKeyUsed(passId) == false) {
                            self.activePasses.upsert(passId, passId);
                            try self.pendingPasses.append(passId);
                        }
                        foundTex = true;
                        break;
                    }
                }

                if (foundTex == false) {
                    std.debug.print("ERROR in OutputLoadSys: Viewport Output TexPassId not found in Pass!\n", .{});
                    return error.OutputTupleNotFound;
                }
            }
        }

        // Manuel Passes (NO Outputs but still inserts dependencies)
        for (manuelPasses) |manuelPass| {
            if (self.activePasses.isKeyUsed(manuelPass)) continue; // already found
            self.activePasses.upsert(manuelPass, manuelPass); // always mark
            if (rc.FRAME_GRAPH_INSERT_MANUAL_DEPENDENCY_PASSES) try self.pendingPasses.append(manuelPass);
        }

        // Backwards Traversal to activate all required Passes
        while (self.pendingPasses.len != 0) {
            const passId = self.pendingPasses.pop().?;

            // Traverse Textures
            const texRange = passLoad.texRanges.getByKey(passId);
            const texRefs = passLoad.texRefs.constSlice()[texRange.first..texRange.last];

            for (texRefs) |texRef| {
                if (texRef.rootPassId) |rootPassId| {
                    if (self.activePasses.isKeyUsed(rootPassId) == false) {
                        self.activePasses.upsert(rootPassId, rootPassId);
                        try self.pendingPasses.append(rootPassId);
                    }
                }
            }

            // Traverse Buffers
            const bufRange = passLoad.bufRanges.getByKey(passId);
            const bufRefs = passLoad.bufRefs.constSlice()[bufRange.first..bufRange.last];

            for (bufRefs) |bufRef| {
                if (bufRef.rootPassId) |rootPassId| {
                    if (self.activePasses.isKeyUsed(rootPassId) == false) {
                        self.activePasses.upsert(rootPassId, rootPassId);
                        try self.pendingPasses.append(rootPassId);
                    }
                }
            }
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("2.Output Load: \n", .{});
            for (self.activePasses.getConstItems()) |passId| {
                const passName = try registry.getPassName(passId);
                std.debug.print(" - Pass: {s}\n", .{passName});
            }
            std.debug.print("\n", .{});
        }
    }
};
