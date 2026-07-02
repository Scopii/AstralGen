const PassDefinition = @import("../../render/types/pass/PassDefinition.zig").PassDefinition;
const PassAccessRange = @import("../../frameBuild/components.zig").PassAccessRange;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const PassData = @import("../1_Pass/PassData.zig").PassData;
const AccessData = @import("../1.5_Access/AccessData.zig").AccessData;
const ResourceData = @import("ResourceData.zig").ResourceData;

// Step 2

pub const ResourceSys = struct {
    pub fn buildResources(resourceData: *ResourceData, accessData: *const AccessData, passData: *const PassData, registryData: *const RegistryData) !void {
        resourceData.bufDescs.clear();
        resourceData.texDescs.clear();

        resourceData.bufMemSizes.clear();
        resourceData.texMemSizeS.clear();

        // Resolve and Save Buffer Descriptions
        for (accessData.bufAccesses.constSlice()) |bufAccess| {
            // const isWrite = (bufAccess.access == .write or bufAccess.bufOutput != null);

            // For Input
            const bufKey1: u16 = bufAccess.bufInput.val();
            if (resourceData.bufDescs.isKeyUsed(bufKey1) == false) {
                const bufDesc1 = try registryData.getBufferDefinition(bufAccess.bufInput);
                resourceData.bufDescs.upsert(bufKey1, bufDesc1);
            }

            // For Output
            const bufKey2: ?u16 = if (bufAccess.bufOutput) |bufOutput| bufOutput.val() else null;
            if (bufKey2) |key2| {
                if (resourceData.bufDescs.isKeyUsed(key2) == false) {
                    const bufDesc2 = try registryData.getBufferDefinition(bufAccess.bufOutput.?);
                    resourceData.bufDescs.upsert(key2, bufDesc2);
                }
            }
        }

        for (resourceData.bufDescs.getConstItems(), 0..) |bufDesc, i| { // If Description is Share = Transient add memSize
            const bufKey = resourceData.bufDescs.getKeyByIndex(@intCast(i));
            if (bufDesc.share == .transient) resourceData.bufMemSizes.upsert(bufKey, bufDesc.guessMemoryCost());
        }

        // Resolve and Save Texture Descriptions (+ Texture Resize Logic for Pass Size)
        for (accessData.texAccesses.constSlice()) |texAccess| {
            const extent = passData.passExtents.getByKey(texAccess.pass.val());
            const isWrite = (texAccess.access == .write or texAccess.texOutput != null);
            const resize = isWrite or rc.PASS_TEXTURE_RESIZE_INCLUDES_READ;

            // For Input
            const texKey1: u16 = texAccess.texInput.val();
            if (resourceData.texDescs.isKeyUsed(texKey1) == false) {
                var texDesc1 = try registryData.getTextureDefinition(texAccess.texInput);
                if (texDesc1.fitPass == true) {
                    texDesc1.width = 0;
                    texDesc1.height = 0;
                }
                resourceData.texDescs.upsert(texKey1, texDesc1);
            }

            var texDesc1 = resourceData.texDescs.getPtrByKey(texKey1);
            if (texDesc1.fitPass == true and resize) {
                texDesc1.width = @max(texDesc1.width, extent.width);
                texDesc1.height = @max(texDesc1.height, extent.height);
            }

            // For Output
            const texKey2: ?u16 = if (texAccess.texOutput) |texOutput| texOutput.val() else null;
            if (texKey2) |key2| {
                if (resourceData.texDescs.isKeyUsed(key2) == false) {
                    var texDesc2 = try registryData.getTextureDefinition(texAccess.texOutput.?);
                    if (texDesc2.fitPass == true) {
                        texDesc2.width = 0;
                        texDesc2.height = 0;
                    }
                    resourceData.texDescs.upsert(key2, texDesc2);
                }

                var texDesc2 = resourceData.texDescs.getPtrByKey(key2);
                if (texDesc2.fitPass == true and resize) {
                    texDesc2.width = @max(texDesc2.width, extent.width);
                    texDesc2.height = @max(texDesc2.height, extent.height);
                }
            }
        }

        for (resourceData.texDescs.getConstItems(), 0..) |texDesc, i| { // If Description is Share = Transient add memSize
            const texKey = resourceData.texDescs.getKeyByIndex(@intCast(i));
            if (texDesc.share == .transient) resourceData.texMemSizeS.upsert(texKey, texDesc.guessMemoryCost());
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("2.ResourceExtractor: \n", .{});
            // Buffer Mem Debug
            for (resourceData.bufMemSizes.getConstItems(), 0..) |memSize, i| {
                const bufKey: u16 = resourceData.bufMemSizes.getKeyByIndex(@intCast(i));
                const bufName = try registryData.getBufferName(.id(bufKey));
                std.debug.print(" {}.Buf ({s}) -> Mem {} Bytes\n", .{ i, bufName, memSize });
            }
            // Texture Mem Debug
            for (resourceData.texMemSizeS.getConstItems(), 0..) |memSize, i| {
                const texKey: u16 = resourceData.texMemSizeS.getKeyByIndex(@intCast(i));
                const texName = try registryData.getTextureName(.id(texKey));
                std.debug.print(" {}.Tex ({s}) -> Mem {} Bytes\n", .{ i, texName, memSize });
            }
            std.debug.print("\n", .{});
        }
    }
};
