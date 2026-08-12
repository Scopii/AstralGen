const RenderRegistryData = @import("../../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const PassLoadData = @import("../1_PassLoad/PassLoad.zig").PassLoadData;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const EngineData = @import("../../EngineData.zig").EngineData;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

pub const OutputLoadData = struct {
    pendingPasses: FixedList(PassId, rc.PASS_MAX) = .{},
    activePasses: LinkedIdMap(PassId, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
};

pub const OutputLoadSys = struct {
    pub fn build(self: *OutputLoadData, passLoad: *const PassLoadData, registry: *const RenderRegistryData, data: *const EngineData) !void {
        self.pendingPasses.clear();
        self.activePasses.clear();

        // Load Producing Passes of Each Viewports Output
        for (data.viewport.activeViewportIds.getConstItems()) |viewportId| {
            const viewport = data.viewport.viewports.getByKey(viewportId.val());

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
                const instanceRange = passLoad.texInstances.getConstItems()[texRange.first..texRange.last];

                var foundTex = false;

                for (instanceRange) |texInstance| {
                    if (texPassId == texInstance.texPassId) {
                        try self.pendingPasses.append(passId);
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

        // Backwards Traversal to activate all required Passes
        while (self.pendingPasses.len != 0) {
            const passId = self.pendingPasses.pop().?;

            if (self.activePasses.isKeyUsed(passId)) continue; // dedupe + cycle guard
            self.activePasses.upsert(passId, passId);

            // Traverse Textures
            const texRange = passLoad.texRanges.getByKey(passId);
            const texInstances = passLoad.texInstances.getConstItems()[texRange.first..texRange.last];

            for (texInstances) |texInstance| {
                if (texInstance.rootPassId) |rootPassId| {
                    if (true) { // REFERENCE VALIDATION
                        const rootTexRange = passLoad.texRanges.getByKey(rootPassId);
                        const rootTexInstances = passLoad.texInstances.getConstItems()[rootTexRange.first..rootTexRange.last];

                        var foundTex = false;

                        for (rootTexInstances) |rootTexInstance| {
                            if (texInstance.texPassId == rootTexInstance.texPassId) {
                                if (self.activePasses.isKeyUsed(rootPassId) == false) try self.pendingPasses.append(rootPassId);
                                foundTex = true;
                                break;
                            }
                        }
                        if (foundTex == false) {
                            std.debug.print("ERROR in OutputLoadSys: Backwards Traversal could not find Texture!\n", .{});
                            return error.OutputTupleNotFound;
                        }
                    } else {
                        if (self.activePasses.isKeyUsed(rootPassId) == false) try self.pendingPasses.append(rootPassId);
                    }
                }
            }

            // Traverse Buffers
            const bufRange = passLoad.bufRanges.getByKey(passId);
            const bufInstances = passLoad.bufInstances.getConstItems()[bufRange.first..bufRange.last];

            for (bufInstances) |bufInstance| {
                if (bufInstance.rootPassId) |rootPassId| {
                    if (true) { // REFERENCE VALIDATION
                        const rootBufRange = passLoad.bufRanges.getByKey(rootPassId);
                        const rootBufInstances = passLoad.bufInstances.getConstItems()[rootBufRange.first..rootBufRange.last];

                        var foundBuf = false;

                        for (rootBufInstances) |rootBufInstance| {
                            if (bufInstance.bufPassId == rootBufInstance.bufPassId) {
                                if (self.activePasses.isKeyUsed(rootPassId) == false) try self.pendingPasses.append(rootPassId);
                                foundBuf = true;
                                break;
                            }
                        }
                        if (foundBuf == false) {
                            std.debug.print("ERROR in OutputLoadSys: Backwards Traversal could not find Buffer!\n", .{});
                            return error.OutputTupleNotFound;
                        }
                    } else {
                        if (self.activePasses.isKeyUsed(rootPassId) == false) try self.pendingPasses.append(rootPassId);
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
