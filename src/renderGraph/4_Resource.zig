const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const TexDesc = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const TexReference = @import("../renderGraph/components.zig").TexReference;
const BufReference = @import("../renderGraph/components.zig").BufReference;
const SimpleIdMap = @import("../.structures/SimpleIdMap.zig").SimpleIdMap;
const Dependancy = @import("../renderGraph/components.zig").Dependancy;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const OutputLoadData = @import("2_OutputLoad.zig").OutputLoadData;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const CompositeData = @import("3_Composite.zig").CompositeData;
const PassLoadData = @import("1_PassLoad.zig").PassLoadData;
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

pub const ResourceData = struct {
    activeBufPassIds: SimpleIdMap(BufPassId, rc.PASS_MAX * rc.BUF_MAX, BufPassId, rc.PASS_MAX * rc.BUF_MAX, 0) = .{},
    activeTexPassIds: SimpleIdMap(TexPassId, rc.PASS_MAX * rc.TEX_MAX, TexPassId, rc.PASS_MAX * rc.TEX_MAX, 0) = .{},

    activeBufDescs: SimpleIdMap(BufDesc, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    activeTexDescs: SimpleIdMap(TexDesc, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    activeTexRefs: FixedList(TexReference, rc.PASS_MAX * rc.TEX_MAX) = .{},
    activeBufRefs: FixedList(BufReference, rc.PASS_MAX * rc.BUF_MAX) = .{},

    dependencies: FixedList(Dependancy, rc.PASS_MAX * rc.RESOURCE_MAX) = .{},
};

pub const ResourceSys = struct {
    pub fn build(self: *ResourceData, passLoad: *const PassLoadData, outputLoad: *const OutputLoadData, composite: *const CompositeData, registry: *const RenderRegistryData) !void {
        self.activeBufPassIds.clear();
        self.activeTexPassIds.clear();
        self.activeBufDescs.clear();
        self.activeTexDescs.clear();
        self.activeBufRefs.clear();
        self.activeTexRefs.clear();
        self.dependencies.clear();

        for (outputLoad.activePasses.getConstItems()) |activePass| {

            // Buffers
            const bufRange = passLoad.bufRanges.getByKey(activePass);
            const bufRefs = passLoad.bufRefs.constSlice()[bufRange.first..bufRange.last];

            for (bufRefs) |bufRef| {
                try self.activeBufRefs.append(bufRef);
                if (bufRef.rootPassId) |rootPassId| try self.dependencies.append(.{ .predecessor = rootPassId, .successor = bufRef.passId });

                const bufPassId = bufRef.bufPassId;

                if (self.activeBufPassIds.isKeyUsed(bufPassId) == false) {
                    self.activeBufPassIds.insert(bufPassId, bufPassId);
                    self.activeBufDescs.insert(bufPassId, try registry.getBufferDefinition(bufPassId));
                }
            }

            // Textures including Resize

            const texRange = passLoad.texRanges.getByKey(activePass);
            const texRefs = passLoad.texRefs.constSlice()[texRange.first..texRange.last];

            for (texRefs) |texRef| {
                try self.activeTexRefs.append(texRef);
                if (texRef.rootPassId) |rootPassId| try self.dependencies.append(.{ .predecessor = rootPassId, .successor = texRef.passId });

                const texPassId = texRef.texPassId;

                const hasExtent = composite.passExtents.isKeyUsed(texRef.passId);

                const isWrite = (texRef.access == .write); //  or texRef.output != null ??
                // const isInPassChain = texRef.rootPassId == null or texRef.rootPassId == activePass;
                const resize = (isWrite or rc.PASS_TEXTURE_RESIZE_INCLUDES_READ); //and isInPassChain;

                if (self.activeTexPassIds.isKeyUsed(texPassId) == false) {
                    self.activeTexPassIds.insert(texPassId, texPassId);
                    self.activeTexDescs.insert(texPassId, try registry.getTextureDefinition(texPassId));
                }

                const texDesc = self.activeTexDescs.getPtrByKey(texPassId);
                if (hasExtent and texDesc.fitPass == true and resize) {
                    const passExtent = composite.passExtents.getByKey(texRef.passId);
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
