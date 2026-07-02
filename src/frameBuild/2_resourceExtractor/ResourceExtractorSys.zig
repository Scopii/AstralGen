const PassDefinition = @import("../../render/types/pass/PassDefinition.zig").PassDefinition;
const PassAccessRange = @import("../../frameBuild/components.zig").PassAccessRange;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const ResourceRegistryData = @import("../0_resourceRegistry/ResourceRegistryData.zig").ResourceRegistryData;
const PassExtractorData = @import("../1_passExtractor/PassExtractorData.zig").PassExtractorData;
const AccessExtractorData = @import("../1.5_accessExtractor/AccessExtractorData.zig").AccessExtractorData;
const ResourceExtractorData = @import("ResourceExtractorData.zig").ResourceExtractorData;

// Step 2

pub const ResourceExtractorSys = struct {
    pub fn buildResources(
        resourceExtractor: *ResourceExtractorData,
        accessExtractor: *const AccessExtractorData,
        passExtractor: *const PassExtractorData,
        resourceRegistry: *const ResourceRegistryData,
    ) !void {
        resourceExtractor.bufDescriptions.clear();
        resourceExtractor.texDescriptions.clear();

        resourceExtractor.bufMemSize.clear();
        resourceExtractor.texMemSize.clear();

        // Resolve and Save Buffer Descriptions
        for (accessExtractor.bufAccesses.constSlice()) |bufAccess| {
            // const isWrite = (bufAccess.access == .write or bufAccess.bufOutput != null);

            // For Input
            const bufKey1: u16 = bufAccess.bufInput.val();
            if (resourceExtractor.bufDescriptions.isKeyUsed(bufKey1) == false) {
                const bufDesc1 = try resourceRegistry.getBufferDefinition(bufAccess.bufInput);
                resourceExtractor.bufDescriptions.upsert(bufKey1, bufDesc1);
            }

            // For Output
            const bufKey2: ?u16 = if (bufAccess.bufOutput) |bufOutput| bufOutput.val() else null;
            if (bufKey2) |key2| {
                if (resourceExtractor.bufDescriptions.isKeyUsed(key2) == false) {
                    const bufDesc2 = try resourceRegistry.getBufferDefinition(bufAccess.bufOutput.?);
                    resourceExtractor.bufDescriptions.upsert(key2, bufDesc2);
                }
            }
        }

        for (resourceExtractor.bufDescriptions.getConstItems(), 0..) |bufDesc, i| { // If Description is Share = Transient add memSize
            const bufKey = resourceExtractor.bufDescriptions.getKeyByIndex(@intCast(i));
            if (bufDesc.share == .transient) resourceExtractor.bufMemSize.upsert(bufKey, bufDesc.guessMemoryCost());
        }

        // Resolve and Save Texture Descriptions (+ Texture Resize Logic for Pass Size)
        for (accessExtractor.texAccesses.constSlice()) |texAccess| {
            const passSize = passExtractor.passResolutions.getByKey(texAccess.pass.val());
            const isWrite = (texAccess.access == .write or texAccess.texOutput != null);
            const resize = isWrite or rc.PASS_TEXTURE_RESIZE_INCLUDES_READ;

            // For Input
            const texKey1: u16 = texAccess.texInput.val();
            if (resourceExtractor.texDescriptions.isKeyUsed(texKey1) == false) {
                var texDesc1 = try resourceRegistry.getTextureDefinition(texAccess.texInput);
                if (texDesc1.fitPass == true) {
                    texDesc1.width = 0;
                    texDesc1.height = 0;
                }
                resourceExtractor.texDescriptions.upsert(texKey1, texDesc1);
            }

            var texDesc1 = resourceExtractor.texDescriptions.getPtrByKey(texKey1);
            if (texDesc1.fitPass == true and resize) {
                texDesc1.width = @max(texDesc1.width, passSize.width);
                texDesc1.height = @max(texDesc1.height, passSize.height);
            }

            // For Output
            const texKey2: ?u16 = if (texAccess.texOutput) |texOutput| texOutput.val() else null;
            if (texKey2) |key2| {
                if (resourceExtractor.texDescriptions.isKeyUsed(key2) == false) {
                    var texDesc2 = try resourceRegistry.getTextureDefinition(texAccess.texOutput.?);
                    if (texDesc2.fitPass == true) {
                        texDesc2.width = 0;
                        texDesc2.height = 0;
                    }
                    resourceExtractor.texDescriptions.upsert(key2, texDesc2);
                }

                var texDesc2 = resourceExtractor.texDescriptions.getPtrByKey(key2);
                if (texDesc2.fitPass == true and resize) {
                    texDesc2.width = @max(texDesc2.width, passSize.width);
                    texDesc2.height = @max(texDesc2.height, passSize.height);
                }
            }
        }

        for (resourceExtractor.texDescriptions.getConstItems(), 0..) |texDesc, i| { // If Description is Share = Transient add memSize
            const texKey = resourceExtractor.texDescriptions.getKeyByIndex(@intCast(i));
            if (texDesc.share == .transient) resourceExtractor.texMemSize.upsert(texKey, texDesc.guessMemoryCost());
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("2.ResourceExtractor: \n", .{});
            // Buffer Mem Debug
            for (resourceExtractor.bufMemSize.getConstItems(), 0..) |memSize, i| {
                const bufKey: u16 = resourceExtractor.bufMemSize.getKeyByIndex(@intCast(i));
                const bufName = try resourceRegistry.getBufferName(.id(bufKey));
                std.debug.print(" {}.Buf ({s}) -> Mem {} Bytes\n", .{ i, bufName, memSize });
            }
            // Texture Mem Debug
            for (resourceExtractor.texMemSize.getConstItems(), 0..) |memSize, i| {
                const texKey: u16 = resourceExtractor.texMemSize.getKeyByIndex(@intCast(i));
                const texName = try resourceRegistry.getTextureName(.id(texKey));
                std.debug.print(" {}.Tex ({s}) -> Mem {} Bytes\n", .{ i, texName, memSize });
            }
            std.debug.print("\n", .{});
        }
    }
};
