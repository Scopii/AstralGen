const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const TextureLifetime = @import("../../frameBuild/components.zig").TextureLifetime;
const BufferLifetime = @import("../../frameBuild/components.zig").BufferLifetime;
const TextureGroup = @import("../../frameBuild/components.zig").TextureGroup;
const BufferGroup = @import("../../frameBuild/components.zig").BufferGroup;
const TexPassId = @import("../components.zig").TexPassId;
const BufPassId = @import("../components.zig").BufPassId;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const ResourceRegistryData = @import("../0_resourceRegistry/ResourceRegistryData.zig").ResourceRegistryData;
const ResourceExtractorData = @import("../2_resourceExtractor/ResourceExtractorData.zig").ResourceExtractorData;
const GraphOptimizerData = @import("../4.5_graphOptimizer/GraphOptimizerData.zig").GraphOptimizerData;
const LifetimeExtractorData = @import("../5_lifetimeExtractor/LifetimeExtractorData.zig").LifetimeExtractorData;
const ResourceMapperData = @import("ResourceMapperData.zig").ResourceMapperData;

// Step 5.1

pub const ResourceMapperSys = struct {
    pub fn buildMapping(
        resourceMapper: *ResourceMapperData,
        resourceExtractor: *const ResourceExtractorData,
        lifetimeExtractor: *const LifetimeExtractorData,
        graphOptimizer: *const GraphOptimizerData,
        resourceRegistry: *const ResourceRegistryData,
    ) !void {
        // Move Last Mapping and Clear current
        resourceMapper.bufMapTransient.clear();
        resourceMapper.bufMapPersistent.clear();
        resourceMapper.texMapTransient.clear();
        resourceMapper.texMapPersistent.clear();

        resourceMapper.lastBufGroupsTransient = resourceMapper.bufGroupsTransient;
        resourceMapper.lastBufGroupsPersistent = resourceMapper.bufGroupsPersistent;
        resourceMapper.lastTexGroupsTransient = resourceMapper.texGroupsTransient;
        resourceMapper.lastTexGroupsPersistent = resourceMapper.texGroupsPersistent;

        resourceMapper.bufGroupsTransient.clear();
        resourceMapper.bufGroupsPersistent.clear();
        resourceMapper.texGroupsTransient.clear();
        resourceMapper.texGroupsPersistent.clear();

        // Buffer

        for (resourceExtractor.bufAccesses.constSlice()) |bufAccess| {
            const bufInputKey: u16 = bufAccess.bufInput.val();
            if (resourceMapper.bufPassIds.isKeyUsed(bufInputKey) == false) resourceMapper.bufPassIds.insert(bufInputKey, bufAccess.bufInput);

            if (bufAccess.bufOutput) |bufOutput| {
                const bufOutputKey: u16 = bufOutput.val();
                if (resourceMapper.bufPassIds.isKeyUsed(bufOutputKey) == false) resourceMapper.bufPassIds.insert(bufOutputKey, bufOutput);
                try resourceMapper.linkedBuffers.append(.{ .in = bufAccess.bufInput, .out = bufAccess.bufOutput }); // moved inside — only append when output exists
            }
        }

        while (resourceMapper.bufPassIds.getLength() > 0) {
            const lastBuffer = resourceMapper.bufPassIds.getLast();
            resourceMapper.bufPassIds.removeLast();
            resourceMapper.allSharedBuffers.upsert(lastBuffer.val(), lastBuffer); // seed directly into allSharedBuffers

            var readIndex: u32 = 0;
            while (readIndex < resourceMapper.allSharedBuffers.getLength()) {
                const sharedBuffer = resourceMapper.allSharedBuffers.getByIndex(readIndex);
                readIndex += 1;

                const linkedBufferLength = resourceMapper.linkedBuffers.len;
                for (0..linkedBufferLength) |linkedIndex| {
                    const curIndex = linkedBufferLength - linkedIndex - 1;
                    const bufLink = resourceMapper.linkedBuffers.constSlice()[curIndex];

                    var isShared = false;
                    if (bufLink.in.val() == sharedBuffer.val()) isShared = true;
                    if (bufLink.out != null and bufLink.out.?.val() == sharedBuffer.val()) isShared = true;

                    if (isShared) {
                        if (resourceMapper.allSharedBuffers.isKeyUsed(bufLink.in.val()) == false) {
                            resourceMapper.allSharedBuffers.upsert(bufLink.in.val(), bufLink.in); // directly into allSharedBuffers
                            resourceMapper.bufPassIds.remove(bufLink.in.val());
                        }
                        if (bufLink.out) |out| {
                            if (resourceMapper.allSharedBuffers.isKeyUsed(out.val()) == false) {
                                resourceMapper.allSharedBuffers.upsert(out.val(), out); // directly into allSharedBuffers
                                resourceMapper.bufPassIds.remove(out.val());
                            }
                        }
                        resourceMapper.linkedBuffers.swapRemove(@intCast(curIndex));
                    }
                }
            }

            // Resolve All Buffers For Validation, Move all to correct Map
            var lastBufPassId: BufPassId = undefined;
            var lastBufDescription: ?BufDesc = null;

            var lastLifetime: ?BufferLifetime = null;
            var root: BufPassId = undefined;

            for (resourceMapper.allSharedBuffers.getConstItems()) |bufPassId| {
                const newBufDesc = resourceExtractor.bufDescriptions.getByKey(bufPassId.val());

                if (lastBufDescription) |lastBufDesc| {
                    try compareBufDesc(lastBufPassId, &lastBufDesc, bufPassId, &newBufDesc, resourceRegistry);
                }

                // Check Root Lifetime
                const newLifetime = lifetimeExtractor.bufLifetimes.getByKey(bufPassId.val());

                if (lastLifetime) |last| {
                    if (newLifetime.earliest < last.earliest or (newLifetime.earliest <= last.earliest and newLifetime.latest < last.latest)) {
                        lastLifetime = newLifetime;
                        root = bufPassId;
                    }
                } else {
                    root = bufPassId;
                    lastLifetime = newLifetime;
                }

                lastBufPassId = bufPassId;
                lastBufDescription = newBufDesc;
            }

            // Create Root Mapping
            for (resourceMapper.allSharedBuffers.getConstItems()) |bufPassId| {
                switch (lastBufDescription.?.share) {
                    .transient => resourceMapper.bufMapTransient.upsert(bufPassId.val(), root),
                    .persistent => resourceMapper.bufMapPersistent.upsert(bufPassId.val(), root),
                }
            }

            // Create Group
            switch (lastBufDescription.?.share) {
                .transient => {
                    const bufGroup = BufferGroup{
                        .rootPass = graphOptimizer.optimizedGraph.getConstItems()[lastLifetime.?.earliest].pass,
                        .rootBuf = root,
                        .bufDesc = lastBufDescription.?,
                        .startMapIndex = @intCast(resourceMapper.bufMapTransient.getLength() - resourceMapper.allSharedBuffers.getLength()),
                        .endMapIndex = @intCast(resourceMapper.bufMapTransient.getLength() - 1),
                    };
                    resourceMapper.bufGroupsTransient.upsert(root.val(), bufGroup);
                },
                .persistent => {
                    const bufGroup = BufferGroup{
                        .rootPass = graphOptimizer.optimizedGraph.getConstItems()[lastLifetime.?.earliest].pass,
                        .rootBuf = root,
                        .bufDesc = lastBufDescription.?,
                        .startMapIndex = @intCast(resourceMapper.bufMapPersistent.getLength() - resourceMapper.allSharedBuffers.getLength()),
                        .endMapIndex = @intCast(resourceMapper.bufMapPersistent.getLength() - 1),
                    };
                    resourceMapper.bufGroupsPersistent.upsert(root.val(), bufGroup);
                },
            }
            resourceMapper.allSharedBuffers.clear();
        }

        // Textures
        for (resourceExtractor.texAccesses.constSlice()) |texAccess| {
            const texInputKey: u16 = texAccess.texInput.val();
            if (resourceMapper.texPassIds.isKeyUsed(texInputKey) == false) resourceMapper.texPassIds.insert(texInputKey, texAccess.texInput);

            if (texAccess.texOutput) |texOutput| {
                const texOutputKey: u16 = texOutput.val();
                if (resourceMapper.texPassIds.isKeyUsed(texOutputKey) == false) resourceMapper.texPassIds.insert(texOutputKey, texOutput);
                try resourceMapper.linkedTextures.append(.{ .in = texAccess.texInput, .out = texAccess.texOutput }); // moved inside — only append when output exists
            }
        }

        while (resourceMapper.texPassIds.getLength() > 0) {
            const lastTexture = resourceMapper.texPassIds.getLast();
            resourceMapper.texPassIds.removeLast();
            resourceMapper.allSharedTextures.upsert(lastTexture.val(), lastTexture); // seed directly into allSharedTextures

            var readIndex: u32 = 0;
            while (readIndex < resourceMapper.allSharedTextures.getLength()) {
                const sharedTexture = resourceMapper.allSharedTextures.getByIndex(readIndex);
                readIndex += 1;

                const linkedTextureLength = resourceMapper.linkedTextures.len;
                for (0..linkedTextureLength) |linkedIndex| {
                    const curIndex = linkedTextureLength - linkedIndex - 1;
                    const texLink = resourceMapper.linkedTextures.constSlice()[curIndex];

                    var isShared = false;
                    if (texLink.in.val() == sharedTexture.val()) isShared = true;
                    if (texLink.out != null and texLink.out.?.val() == sharedTexture.val()) isShared = true;

                    if (isShared) {
                        if (resourceMapper.allSharedTextures.isKeyUsed(texLink.in.val()) == false) {
                            resourceMapper.allSharedTextures.upsert(texLink.in.val(), texLink.in); // directly into allSharedTextures
                            resourceMapper.texPassIds.remove(texLink.in.val());
                        }
                        if (texLink.out) |out| {
                            if (resourceMapper.allSharedTextures.isKeyUsed(out.val()) == false) {
                                resourceMapper.allSharedTextures.upsert(out.val(), out); // directly into allSharedTextures
                                resourceMapper.texPassIds.remove(out.val());
                            }
                        }
                        resourceMapper.linkedTextures.swapRemove(@intCast(curIndex));
                    }
                }
            }

            var lastTexPassId: TexPassId = undefined;
            var lastTexDescription: ?TexDesc = null;

            var lastLifetime: ?TextureLifetime = null;
            var root: TexPassId = undefined;

            for (resourceMapper.allSharedTextures.getConstItems()) |texPassId| {
                const newTexDesc = resourceExtractor.texDescriptions.getByKey(texPassId.val());

                if (lastTexDescription) |lastTexDesc| {
                    try compareTexDesc(lastTexPassId, &lastTexDesc, texPassId, &newTexDesc, resourceRegistry);
                }

                // Check Root Lifetime
                const newLifetime = lifetimeExtractor.texLifetimes.getByKey(texPassId.val());

                if (lastLifetime) |last| {
                    if (newLifetime.earliest < last.earliest or (newLifetime.earliest <= last.earliest and newLifetime.latest < last.latest)) {
                        lastLifetime = newLifetime;
                        root = texPassId;
                    }
                } else {
                    root = texPassId;
                    lastLifetime = newLifetime;
                }

                lastTexPassId = texPassId;
                lastTexDescription = newTexDesc;
            }

            // Root Mappings
            for (resourceMapper.allSharedTextures.getConstItems()) |texPassId| {
                switch (lastTexDescription.?.share) {
                    .transient => resourceMapper.texMapTransient.upsert(texPassId.val(), root),
                    .persistent => resourceMapper.texMapPersistent.upsert(texPassId.val(), root),
                }
            }

            // Create Group
            switch (lastTexDescription.?.share) {
                .transient => {
                    const texGroup = TextureGroup{
                        .rootPass = graphOptimizer.optimizedGraph.getConstItems()[lastLifetime.?.earliest].pass,
                        .rootTex = root,
                        .texDesc = lastTexDescription.?,
                        .startMapIndex = @intCast(resourceMapper.texMapTransient.getLength() - resourceMapper.allSharedTextures.getLength()),
                        .endMapIndex = @intCast(resourceMapper.texMapTransient.getLength() - 1),
                    };
                    resourceMapper.texGroupsTransient.upsert(root.val(), texGroup);
                },
                .persistent => {
                    const texGroup = TextureGroup{
                        .rootPass = graphOptimizer.optimizedGraph.getConstItems()[lastLifetime.?.earliest].pass,
                        .rootTex = root,
                        .texDesc = lastTexDescription.?,
                        .startMapIndex = @intCast(resourceMapper.texMapPersistent.getLength() - resourceMapper.allSharedTextures.getLength()),
                        .endMapIndex = @intCast(resourceMapper.texMapPersistent.getLength() - 1),
                    };
                    resourceMapper.texGroupsPersistent.upsert(root.val(), texGroup);
                },
            }

            resourceMapper.allSharedTextures.clear();
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.1.ResourceMapper: \n", .{});

            std.debug.print("Previous: \n", .{});
            // Buffer Debug
            for (resourceMapper.lastBufGroupsPersistent.getConstItems(), 0..) |group, i| {
                const rootBufName = try resourceRegistry.getBufferName(group.rootBuf);
                const rootPassName = try resourceRegistry.getPassName(group.rootPass);
                std.debug.print("BufGroup (Persistent {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootBufName, rootPassName, group.startMapIndex, group.endMapIndex });
            }

            for (resourceMapper.lastBufGroupsTransient.getConstItems(), 0..) |group, i| {
                const rootBufName = try resourceRegistry.getBufferName(group.rootBuf);
                const rootPassName = try resourceRegistry.getPassName(group.rootPass);
                std.debug.print("BufGroup (Transient {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootBufName, rootPassName, group.startMapIndex, group.endMapIndex });
            }

            // Group Debug Textures
            for (resourceMapper.lastTexGroupsPersistent.getConstItems(), 0..) |group, i| {
                const rootTexName = try resourceRegistry.getTextureName(group.rootTex);
                const rootPassName = try resourceRegistry.getPassName(group.rootPass);
                std.debug.print("TexGroup (Persistent {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootTexName, rootPassName, group.startMapIndex, group.endMapIndex });
            }

            for (resourceMapper.lastTexGroupsTransient.getConstItems(), 0..) |group, i| {
                const rootTexName = try resourceRegistry.getTextureName(group.rootTex);
                const rootPassName = try resourceRegistry.getPassName(group.rootPass);
                std.debug.print("TexGroup (Transient {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootTexName, rootPassName, group.startMapIndex, group.endMapIndex });
            }

            std.debug.print("\n", .{});
            std.debug.print("Current: \n", .{});

            // Group Debug Buffers
            for (resourceMapper.bufGroupsPersistent.getConstItems(), 0..) |group, i| {
                const rootBufName = try resourceRegistry.getBufferName(group.rootBuf);
                const rootPassName = try resourceRegistry.getPassName(group.rootPass);
                std.debug.print("BufGroup (Persistent {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootBufName, rootPassName, group.startMapIndex, group.endMapIndex });

                for (group.startMapIndex..group.endMapIndex + 1, 0..) |mapIndex, counter| {
                    const bufKey: u16 = resourceMapper.bufMapPersistent.getKeyByIndex(@intCast(mapIndex));
                    const bufName = try resourceRegistry.getBufferName(.id(bufKey));
                    std.debug.print("     -> {}. {s}\n", .{ counter, bufName });
                }
            }

            for (resourceMapper.bufGroupsTransient.getConstItems(), 0..) |group, i| {
                const rootBufName = try resourceRegistry.getBufferName(group.rootBuf);
                const rootPassName = try resourceRegistry.getPassName(group.rootPass);
                std.debug.print("BufGroup (Transient {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootBufName, rootPassName, group.startMapIndex, group.endMapIndex });

                for (group.startMapIndex..group.endMapIndex + 1, 0..) |mapIndex, counter| {
                    const bufKey: u16 = resourceMapper.bufMapTransient.getKeyByIndex(@intCast(mapIndex));
                    const bufName = try resourceRegistry.getBufferName(.id(bufKey));
                    std.debug.print("     -> {}. {s}\n", .{ counter, bufName });
                }
            }

            // Group Debug Textures
            for (resourceMapper.texGroupsPersistent.getConstItems(), 0..) |group, i| {
                const rootTexName = try resourceRegistry.getTextureName(group.rootTex);
                const rootPassName = try resourceRegistry.getPassName(group.rootPass);
                std.debug.print("TexGroup (Persistent {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootTexName, rootPassName, group.startMapIndex, group.endMapIndex });

                for (group.startMapIndex..group.endMapIndex + 1, 0..) |mapIndex, counter| {
                    const texKey: u16 = resourceMapper.texMapPersistent.getKeyByIndex(@intCast(mapIndex));
                    const texName = try resourceRegistry.getTextureName(.id(texKey));
                    std.debug.print("     -> {}. {s}\n", .{ counter, texName });
                }
            }

            for (resourceMapper.texGroupsTransient.getConstItems(), 0..) |group, i| {
                const rootTexName = try resourceRegistry.getTextureName(group.rootTex);
                const rootPassName = try resourceRegistry.getPassName(group.rootPass);
                std.debug.print("TexGroup (Transient {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootTexName, rootPassName, group.startMapIndex, group.endMapIndex });

                for (group.startMapIndex..group.endMapIndex + 1, 0..) |mapIndex, counter| {
                    const texKey: u16 = resourceMapper.texMapTransient.getKeyByIndex(@intCast(mapIndex));
                    const texName = try resourceRegistry.getTextureName(.id(texKey));
                    std.debug.print("     -> {}. {s}\n", .{ counter, texName });
                }
            }

            std.debug.print("\n", .{});
        }
    }
};

fn compareBufDesc(bufId1: BufPassId, bufDesc1: *const BufDesc, bufId2: BufPassId, bufDesc2: *const BufDesc, resourceRegistry: *const ResourceRegistryData) !void {
    const equal = if (std.meta.eql(bufDesc1.*, bufDesc2.*)) true else false;

    const bufName1 = try resourceRegistry.getBufferName(bufId1);
    const bufName2 = try resourceRegistry.getBufferName(bufId2);

    if (equal == false) {
        std.debug.print("ERROR: ResourceMapperSys: Buffer Descriptions dont match \n({s}:{})\n({s}:{})\n", .{ bufName1, bufDesc1, bufName2, bufDesc2 });
        return error.BufferDescriptionsDontMatch;
    }
}

fn compareTexDesc(texId1: TexPassId, texDesc1: *const TexDesc, texId2: TexPassId, texDesc2: *const TexDesc, resourceRegistry: *const ResourceRegistryData) !void {
    const equal = if (std.meta.eql(texDesc1.*, texDesc2.*)) true else false;

    const texName1 = try resourceRegistry.getTextureName(texId1);
    const texName2 = try resourceRegistry.getTextureName(texId2);

    if (equal == false) {
        std.debug.print("ERROR: ResourceMapperSys: Texture Descriptions dont match \n({s}:{})\n({s}:{})\n", .{ texName1, texDesc1, texName2, texDesc2 });
        return error.BufferDescriptionsDontMatch;
    }
}
