const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const TexDesc = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const TexReference = @import("../renderGraph/components.zig").TexReference;
const BufReference = @import("../renderGraph/components.zig").BufReference;
const SimpleIdMap = @import("../.structures/SimpleIdMap.zig").SimpleIdMap;
const LinkedIdMap = @import("../.structures/LinkedIdMap.zig").LinkedIdMap;
const Dependancy = @import("../renderGraph/components.zig").Dependency;
const DependencyData = @import("3.5_Dependency.zig").DependencyData;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const OutputLoadData = @import("2_OutputLoad.zig").OutputLoadData;
const CompositeData = @import("5.2_Composite.zig").CompositeData;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const PassLoadData = @import("1_PassLoad.zig").PassLoadData;
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

pub const ResourceData = struct {
    activeBufDescs: LinkedIdMap(BufDesc, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    activeTexDescs: LinkedIdMap(TexDesc, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},
};

pub const ResourceSys = struct {
    pub fn build(self: *ResourceData, passLoad: *const PassLoadData, composite: *const CompositeData, dependency: *const DependencyData, registry: *const RenderRegistryData) !void {
        self.activeBufDescs.clear();
        self.activeTexDescs.clear();

        // Buffers
        for (dependency.activeBufRefs.constSlice()) |bufRef| {
            if (self.activeBufDescs.isKeyUsed(bufRef.bufPassId) == false) {
                self.activeBufDescs.insert(bufRef.bufPassId, try registry.getBufferDefinition(bufRef.bufPassId));
            }
        }

        // Textures including Resize
        for (dependency.activeTexRefs.constSlice()) |texRef| {
            if (self.activeTexDescs.isKeyUsed(texRef.texPassId) == false) {
                var texDef = try registry.getTextureDefinition(texRef.texPassId);

                const neededUsage = passLoad.texUsages.getByKey(texRef.texPassId);
                texDef.texUse = neededUsage;

                const needsSampled: bool =  neededUsage.sampled or neededUsage.colorAtt or neededUsage.depthAtt;
                const needsStorage: bool = neededUsage.storage;

                if (needsSampled == true and needsStorage == true) texDef.descriptors = .StorageSampled;
                if (needsSampled == false and needsStorage == true) texDef.descriptors = .StorageOnly;
                if (needsSampled == true and needsStorage == false) texDef.descriptors = .SampledOnly;

                self.activeTexDescs.insert(texRef.texPassId, texDef);
            }

            if (texRef.access != .write) continue;
            if (composite.passExtents.isKeyUsed(texRef.passId) == false) continue;

            const texDesc = self.activeTexDescs.getPtrByKey(texRef.texPassId);
            if (texDesc.fitPass == false) continue;

            const passExtent = composite.passExtents.getByKey(texRef.passId);
            texDesc.width = @max(texDesc.width, passExtent.width);
            texDesc.height = @max(texDesc.height, passExtent.height);
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.5.Resource: \n", .{});
            for (self.activeBufDescs.getConstItems(), 0..) |_, index| {
                const bufPassId = self.activeBufDescs.getKeyByIndex(@intCast(index));
                const bufName = try registry.getBufferName(bufPassId);
                std.debug.print("    -> Buffer {}: {s}\n", .{ index, bufName });
            }

            for (self.activeTexDescs.getConstItems(), 0..) |_, index| {
                const texPassId = self.activeTexDescs.getKeyByIndex(@intCast(index));
                const texName = try registry.getTextureName(texPassId);
                std.debug.print("    -> Texture {}: {s}\n", .{ index, texName });
            }
            std.debug.print("\n", .{});
        }
    }
};
