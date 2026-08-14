const RenderRegistryData = @import("../../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const OutputLoadData = @import("../2_OutputLoad/OutputLoad.zig").OutputLoadData;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const CompositeData = @import("../3_Composite/Composite.zig").CompositeData;
const TexInstance = @import("../../renderGraph/components.zig").TexInstance;
const BufInstance = @import("../../renderGraph/components.zig").BufInstance;
const Dependancy = @import("../../renderGraph/components.zig").Dependancy;
const PassLoadData = @import("../1_PassLoad/PassLoad.zig").PassLoadData;
const FixedList = @import("../../.structures/FixedList.zig").FixedList;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

pub const ResourceData = struct {
    activeBufPassIds: LinkedIdMap(BufPassId, rc.PASS_MAX * rc.BUF_MAX, BufPassId, rc.PASS_MAX * rc.BUF_MAX, 0) = .{},
    activeTexPassIds: LinkedIdMap(TexPassId, rc.PASS_MAX * rc.TEX_MAX, TexPassId, rc.PASS_MAX * rc.TEX_MAX, 0) = .{},

    bufDescs: LinkedIdMap(BufDesc, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    texDescs: LinkedIdMap(TexDesc, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    activeTexInstances: FixedList(TexInstance, rc.PASS_MAX * rc.TEX_MAX) = .{},
    activeBufInstances: FixedList(BufInstance, rc.PASS_MAX * rc.BUF_MAX) = .{},

    dependencies: FixedList(Dependancy, rc.PASS_MAX * rc.RESOURCE_MAX) = .{},

    // memSizes: LinkedIdMap(u64, rc.RESOURCE_MAX, ResPassId, rc.RESOURCE_MAX, 0) = .{}, // Only used for transient Resources
};

pub const ResourceSys = struct {
    pub fn build(self: *ResourceData, passLoad: *const PassLoadData, outputLoad: *const OutputLoadData, composite: *const CompositeData, registry: *const RenderRegistryData) !void {
        self.activeBufPassIds.clear();
        self.activeTexPassIds.clear();
        self.bufDescs.clear();
        self.texDescs.clear();
        self.activeBufInstances.clear();
        self.activeTexInstances.clear();
        self.dependencies.clear();

        for (outputLoad.activePasses.getConstItems()) |activePass| {

            // Buffers
            const bufRange = passLoad.bufRanges.getByKey(activePass);
            const bufInstances = passLoad.bufInstances.getConstItems()[bufRange.first..bufRange.last];

            for (bufInstances) |bufInst| {
                try self.activeBufInstances.append(bufInst);
                if (bufInst.rootPassId) |rootPassId| try self.dependencies.append(.{ .predecessor = rootPassId, .successor = bufInst.passId });

                const bufPassId = bufInst.bufPassId;

                if (self.activeBufPassIds.isKeyUsed(bufPassId) == false) {
                    self.activeBufPassIds.insert(bufPassId, bufPassId);
                    self.bufDescs.insert(bufPassId, try registry.getBufferDefinition(bufPassId));
                }
            }

            // Textures including Resize

            const texRange = passLoad.texRanges.getByKey(activePass);
            const texInstances = passLoad.texInstances.getConstItems()[texRange.first..texRange.last];

            for (texInstances) |texInst| {
                try self.activeTexInstances.append(texInst);
                if (texInst.rootPassId) |rootPassId| try self.dependencies.append(.{ .predecessor = rootPassId, .successor = texInst.passId });

                const texPassId = texInst.texPassId;

                const passExtent = composite.newPassExtents.getByKey(texInst.passId);
                const isWrite = (texInst.access == .write); //  or texInst.output != null ??
                // const isInPassChain = texInst.rootPassId == null or texInst.rootPassId == activePass;
                const resize = (isWrite or rc.PASS_TEXTURE_RESIZE_INCLUDES_READ); //and isInPassChain;

                if (self.activeTexPassIds.isKeyUsed(texPassId) == false) {
                    self.activeTexPassIds.insert(texPassId, texPassId);
                    self.texDescs.insert(texPassId, try registry.getTextureDefinition(texPassId));
                }

                const texDesc = self.texDescs.getPtrByKey(texPassId);
                if (texDesc.fitPass == true and resize) {
                    texDesc.width = @max(texDesc.width, passExtent.width);
                    texDesc.height = @max(texDesc.height, passExtent.height);
                }
            }
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("4.OutputLoad: \n", .{});
            for (self.activeBufPassIds.getConstItems(), 0..) |bufPassId, index| {
                const bufName = try registry.getBufferName(bufPassId);
                std.debug.print("    -> Buffer {}: {s}\n", .{ index, bufName });
            }
            for (self.activeTexPassIds.getConstItems(), 0..) |texPassId, index| {
                const texName = try registry.getTextureName(texPassId);
                std.debug.print("    -> Texture {}: {s}\n", .{ index, texName });
            }
            std.debug.print("\n", .{});
        }
    }
};
