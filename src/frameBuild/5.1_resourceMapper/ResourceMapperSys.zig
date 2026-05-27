const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const TextureLifetime = @import("../../frameBuild/components.zig").TextureLifetime;
const BufferLifetime = @import("../../frameBuild/components.zig").BufferLifetime;
const TextureGroup = @import("../../frameBuild/components.zig").TextureGroup;
const BufferGroup = @import("../../frameBuild/components.zig").BufferGroup;
const TextureEnum = @import("../enums.zig").TextureEnum;
const BufferEnum = @import("../enums.zig").BufferEnum;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const ResourceExtractorData = @import("../2_resourceExtractor/ResourceExtractorData.zig").ResourceExtractorData;
const LifetimeExtractorData = @import("../5_lifetimeExtractor/LifetimeExtractorData.zig").LifetimeExtractorData;
const GraphOptimizerData = @import("../4.5_graphOptimizer/GraphOptimizerData.zig").GraphOptimizerData;
const ResourceMapperData = @import("ResourceMapperData.zig").ResourceMapperData;

// Step 5.1

pub const ResourceMapperSys = struct {
    pub fn buildMapping(
        resourceMapper: *ResourceMapperData,
        resourceExtractor: *const ResourceExtractorData,
        lifetimeExtractor: *const LifetimeExtractorData,
        graphOptimizer: *const GraphOptimizerData,
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
            const bufInputKey: u16 = @intFromEnum(bufAccess.bufInput);
            if (resourceMapper.bufferEnums.isKeyUsed(bufInputKey) == false) resourceMapper.bufferEnums.insert(bufInputKey, bufAccess.bufInput);

            if (bufAccess.bufOutput) |bufOutput| {
                const bufOutputKey: u16 = @intFromEnum(bufOutput);
                if (resourceMapper.bufferEnums.isKeyUsed(bufOutputKey) == false) resourceMapper.bufferEnums.insert(bufOutputKey, bufOutput);
                try resourceMapper.linkedBuffers.append(.{ .in = bufAccess.bufInput, .out = bufAccess.bufOutput }); // moved inside — only append when output exists
            }
        }

        while (resourceMapper.bufferEnums.getLength() > 0) {
            const lastBuffer = resourceMapper.bufferEnums.getLast();
            resourceMapper.bufferEnums.removeLast();
            resourceMapper.allSharedBuffers.upsert(@intFromEnum(lastBuffer), lastBuffer); // seed directly into allSharedBuffers

            var readIndex: u32 = 0;
            while (readIndex < resourceMapper.allSharedBuffers.getLength()) {
                const sharedBuffer = resourceMapper.allSharedBuffers.getByIndex(readIndex);
                readIndex += 1;

                const linkedBufferLength = resourceMapper.linkedBuffers.len;
                for (0..linkedBufferLength) |linkedIndex| {
                    const curIndex = linkedBufferLength - linkedIndex - 1;
                    const bufLink = resourceMapper.linkedBuffers.constSlice()[curIndex];

                    var isShared = false;
                    if (bufLink.in == sharedBuffer) isShared = true;
                    if (bufLink.out != null and bufLink.out == sharedBuffer) isShared = true;

                    if (isShared) {
                        if (resourceMapper.allSharedBuffers.isKeyUsed(@intFromEnum(bufLink.in)) == false) {
                            resourceMapper.allSharedBuffers.upsert(@intFromEnum(bufLink.in), bufLink.in); // directly into allSharedBuffers
                            resourceMapper.bufferEnums.remove(@intFromEnum(bufLink.in));
                        }
                        if (bufLink.out) |out| {
                            if (resourceMapper.allSharedBuffers.isKeyUsed(@intFromEnum(out)) == false) {
                                resourceMapper.allSharedBuffers.upsert(@intFromEnum(out), out); // directly into allSharedBuffers
                                resourceMapper.bufferEnums.remove(@intFromEnum(out));
                            }
                        }
                        resourceMapper.linkedBuffers.swapRemove(@intCast(curIndex));
                    }
                }
            }

            // Resolve All Buffers For Validation, Move all to correct Map
            var lastBufEnum: BufferEnum = undefined;
            var lastBufDescription: ?BufDesc = null;

            var lastLifetime: ?BufferLifetime = null;
            var root: BufferEnum = undefined;

            for (resourceMapper.allSharedBuffers.getConstItems()) |bufEnum| {
                const newBufDesc = resourceExtractor.bufDescriptions.getByKey(@intCast(@intFromEnum(bufEnum)));

                if (lastBufDescription) |lastBufDesc| {
                    try compareBufDesc(lastBufEnum, &lastBufDesc, bufEnum, &newBufDesc);
                }

                // Check Root Lifetime
                const newLifetime = lifetimeExtractor.bufLifetimes.getByKey(@intFromEnum(bufEnum));

                if (lastLifetime) |last| {
                    if (newLifetime.earliest < last.earliest or (newLifetime.earliest <= last.earliest and newLifetime.latest < last.latest)) {
                        lastLifetime = newLifetime;
                        root = bufEnum;
                    }
                } else {
                    root = bufEnum;
                    lastLifetime = newLifetime;
                }

                lastBufEnum = bufEnum;
                lastBufDescription = newBufDesc;
            }

            // Create Root Mapping
            for (resourceMapper.allSharedBuffers.getConstItems()) |bufEnum| {
                switch (lastBufDescription.?.share) {
                    .transient => resourceMapper.bufMapTransient.upsert(@intFromEnum(bufEnum), root),
                    .persistent => resourceMapper.bufMapPersistent.upsert(@intFromEnum(bufEnum), root),
                }
            }

            // Create Group
            switch (lastBufDescription.?.share) {
                .transient => {
                    const bufGroup = BufferGroup{
                        .rootPass = graphOptimizer.optimizedGraph.getConstItems()[lastLifetime.?.earliest].passEnum,
                        .rootBuf = root,
                        .bufDesc = lastBufDescription.?,
                        .startMapIndex = @intCast(resourceMapper.bufMapTransient.getLength() - resourceMapper.allSharedBuffers.getLength()),
                        .endMapIndex = @intCast(resourceMapper.bufMapTransient.getLength() - 1),
                    };
                    resourceMapper.bufGroupsTransient.upsert(@intFromEnum(root), bufGroup);
                },
                .persistent => {
                    const bufGroup = BufferGroup{
                        .rootPass = graphOptimizer.optimizedGraph.getConstItems()[lastLifetime.?.earliest].passEnum,
                        .rootBuf = root,
                        .bufDesc = lastBufDescription.?,
                        .startMapIndex = @intCast(resourceMapper.bufMapPersistent.getLength() - resourceMapper.allSharedBuffers.getLength()),
                        .endMapIndex = @intCast(resourceMapper.bufMapPersistent.getLength() - 1),
                    };
                    resourceMapper.bufGroupsPersistent.upsert(@intFromEnum(root), bufGroup);
                },
            }
            resourceMapper.allSharedBuffers.clear();
        }

        // Textures
        for (resourceExtractor.texAccesses.constSlice()) |texAccess| {
            const texInputKey: u16 = @intFromEnum(texAccess.texInput);
            if (resourceMapper.textureEnums.isKeyUsed(texInputKey) == false) resourceMapper.textureEnums.insert(texInputKey, texAccess.texInput);

            if (texAccess.texOutput) |texOutput| {
                const texOutputKey: u16 = @intFromEnum(texOutput);
                if (resourceMapper.textureEnums.isKeyUsed(texOutputKey) == false) resourceMapper.textureEnums.insert(texOutputKey, texOutput);
                try resourceMapper.linkedTextures.append(.{ .in = texAccess.texInput, .out = texAccess.texOutput }); // moved inside — only append when output exists
            }
        }

        while (resourceMapper.textureEnums.getLength() > 0) {
            const lastTexture = resourceMapper.textureEnums.getLast();
            resourceMapper.textureEnums.removeLast();
            resourceMapper.allSharedTextures.upsert(@intFromEnum(lastTexture), lastTexture); // seed directly into allSharedTextures

            var readIndex: u32 = 0;
            while (readIndex < resourceMapper.allSharedTextures.getLength()) {
                const sharedTexture = resourceMapper.allSharedTextures.getByIndex(readIndex);
                readIndex += 1;

                const linkedTextureLength = resourceMapper.linkedTextures.len;
                for (0..linkedTextureLength) |linkedIndex| {
                    const curIndex = linkedTextureLength - linkedIndex - 1;
                    const texLink = resourceMapper.linkedTextures.constSlice()[curIndex];

                    var isShared = false;
                    if (texLink.in == sharedTexture) isShared = true;
                    if (texLink.out != null and texLink.out == sharedTexture) isShared = true;

                    if (isShared) {
                        if (resourceMapper.allSharedTextures.isKeyUsed(@intFromEnum(texLink.in)) == false) {
                            resourceMapper.allSharedTextures.upsert(@intFromEnum(texLink.in), texLink.in); // directly into allSharedTextures
                            resourceMapper.textureEnums.remove(@intFromEnum(texLink.in));
                        }
                        if (texLink.out) |out| {
                            if (resourceMapper.allSharedTextures.isKeyUsed(@intFromEnum(out)) == false) {
                                resourceMapper.allSharedTextures.upsert(@intFromEnum(out), out); // directly into allSharedTextures
                                resourceMapper.textureEnums.remove(@intFromEnum(out));
                            }
                        }
                        resourceMapper.linkedTextures.swapRemove(@intCast(curIndex));
                    }
                }
            }

            var lastTexEnum: TextureEnum = undefined;
            var lastTexDescription: ?TexDesc = null;

            var lastLifetime: ?TextureLifetime = null;
            var root: TextureEnum = undefined;

            for (resourceMapper.allSharedTextures.getConstItems()) |texEnum| {
                const newTexDesc = resourceExtractor.texDescriptions.getByKey(@intCast(@intFromEnum(texEnum)));

                if (lastTexDescription) |lastTexDesc| {
                    try compareTexDesc(lastTexEnum, &lastTexDesc, texEnum, &newTexDesc);
                }

                // Check Root Lifetime
                const newLifetime = lifetimeExtractor.texLifetimes.getByKey(@intFromEnum(texEnum));

                if (lastLifetime) |last| {
                    if (newLifetime.earliest < last.earliest or (newLifetime.earliest <= last.earliest and newLifetime.latest < last.latest)) {
                        lastLifetime = newLifetime;
                        root = texEnum;
                    }
                } else {
                    root = texEnum;
                    lastLifetime = newLifetime;
                }

                lastTexEnum = texEnum;
                lastTexDescription = newTexDesc;
            }

            // Root Mappings
            for (resourceMapper.allSharedTextures.getConstItems()) |texEnum| {
                switch (lastTexDescription.?.share) {
                    .transient => resourceMapper.texMapTransient.upsert(@intFromEnum(texEnum), root),
                    .persistent => resourceMapper.texMapPersistent.upsert(@intFromEnum(texEnum), root),
                }
            }

            // Create Group
            switch (lastTexDescription.?.share) {
                .transient => {
                    const texGroup = TextureGroup{
                        .rootPass = graphOptimizer.optimizedGraph.getConstItems()[lastLifetime.?.earliest].passEnum,
                        .rootTex = root,
                        .texDesc = lastTexDescription.?,
                        .startMapIndex = @intCast(resourceMapper.texMapTransient.getLength() - resourceMapper.allSharedTextures.getLength()),
                        .endMapIndex = @intCast(resourceMapper.texMapTransient.getLength() - 1),
                    };
                    resourceMapper.texGroupsTransient.upsert(@intFromEnum(root), texGroup);
                },
                .persistent => {
                    const texGroup = TextureGroup{
                        .rootPass = graphOptimizer.optimizedGraph.getConstItems()[lastLifetime.?.earliest].passEnum,
                        .rootTex = root,
                        .texDesc = lastTexDescription.?,
                        .startMapIndex = @intCast(resourceMapper.texMapPersistent.getLength() - resourceMapper.allSharedTextures.getLength()),
                        .endMapIndex = @intCast(resourceMapper.texMapPersistent.getLength() - 1),
                    };
                    resourceMapper.texGroupsPersistent.upsert(@intFromEnum(root), texGroup);
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
                std.debug.print("BufGroup (Persistent {}) (RootRes {}) (RootPass {}) (mapIndex {} -> {})\n", .{ i, group.rootBuf, group.rootPass, group.startMapIndex, group.endMapIndex });
            }

            for (resourceMapper.lastBufGroupsTransient.getConstItems(), 0..) |group, i| {
                std.debug.print("BufGroup (Transient {}) (RootRes {}) (RootPass {}) (mapIndex {} -> {})\n", .{ i, group.rootBuf, group.rootPass, group.startMapIndex, group.endMapIndex });
            }

            // Group Debug Textures
            for (resourceMapper.lastTexGroupsPersistent.getConstItems(), 0..) |group, i| {
                std.debug.print("TexGroup (Persistent {}) (RootRes {}) (RootPass {}) (mapIndex {} -> {})\n", .{ i, group.rootTex, group.rootPass, group.startMapIndex, group.endMapIndex });
            }

            for (resourceMapper.lastTexGroupsTransient.getConstItems(), 0..) |group, i| {
                std.debug.print("TexGroup (Transient {}) (RootRes {}) (RootPass {}) (mapIndex {} -> {})\n", .{ i, group.rootTex, group.rootPass, group.startMapIndex, group.endMapIndex });
            }

            std.debug.print("\n", .{});
            std.debug.print("Current: \n", .{});

            // Group Debug Buffers
            for (resourceMapper.bufGroupsPersistent.getConstItems(), 0..) |group, i| {
                std.debug.print("BufGroup (Persistent {}) (RootRes {}) (RootPass {}) (mapIndex {} -> {})\n", .{ i, group.rootBuf, group.rootPass, group.startMapIndex, group.endMapIndex });
                for (group.startMapIndex..group.endMapIndex + 1, 0..) |mapIndex, counter| {
                    const castedIndex: u32 = @intCast(mapIndex);
                    const bufEnum: BufferEnum = @enumFromInt(resourceMapper.bufMapPersistent.getKeyByIndex(castedIndex));
                    std.debug.print("     -> {}. {s}\n", .{ counter, @tagName(bufEnum) });
                }
            }

            for (resourceMapper.bufGroupsTransient.getConstItems(), 0..) |group, i| {
                std.debug.print("BufGroup (Transient {}) (RootRes {}) (RootPass {}) (mapIndex {} -> {})\n", .{ i, group.rootBuf, group.rootPass, group.startMapIndex, group.endMapIndex });
                for (group.startMapIndex..group.endMapIndex + 1, 0..) |mapIndex, counter| {
                    const castedIndex: u32 = @intCast(mapIndex);
                    const bufEnum: BufferEnum = @enumFromInt(resourceMapper.bufMapTransient.getKeyByIndex(castedIndex));
                    std.debug.print("     -> {}. {s}\n", .{ counter, @tagName(bufEnum) });
                }
            }

            // Group Debug Textures
            for (resourceMapper.texGroupsPersistent.getConstItems(), 0..) |group, i| {
                std.debug.print("TexGroup (Persistent {}) (RootRes {}) (RootPass {}) (mapIndex {} -> {})\n", .{ i, group.rootTex, group.rootPass, group.startMapIndex, group.endMapIndex });
                for (group.startMapIndex..group.endMapIndex + 1, 0..) |mapIndex, counter| {
                    const castedIndex: u32 = @intCast(mapIndex);
                    const texEnum: TextureEnum = @enumFromInt(resourceMapper.texMapPersistent.getKeyByIndex(castedIndex));
                    std.debug.print("     -> {}. {s}\n", .{ counter, @tagName(texEnum) });
                }
            }

            for (resourceMapper.texGroupsTransient.getConstItems(), 0..) |group, i| {
                std.debug.print("TexGroup (Transient {}) (RootRes {}) (RootPass {}) (mapIndex {} -> {})\n", .{ i, group.rootTex, group.rootPass, group.startMapIndex, group.endMapIndex });
                for (group.startMapIndex..group.endMapIndex + 1, 0..) |mapIndex, counter| {
                    const castedIndex: u32 = @intCast(mapIndex);
                    const texEnum: TextureEnum = @enumFromInt(resourceMapper.texMapTransient.getKeyByIndex(castedIndex));
                    std.debug.print("     -> {}. {s}\n", .{ counter, @tagName(texEnum) });
                }
            }

            std.debug.print("\n", .{});
        }
    }
};

fn compareBufDesc(bufEnum1: BufferEnum, bufDesc1: *const BufDesc, bufEnum2: BufferEnum, bufDesc2: *const BufDesc) !void {
    const equal = if (std.meta.eql(bufDesc1.*, bufDesc2.*)) true else false;

    if (equal == false) {
        std.debug.print("ERROR: ResourceMapperSys: Buffer Descriptions dont match \n({s}:{})\n({s}:{})\n", .{ @tagName(bufEnum1), bufDesc1, @tagName(bufEnum2), bufDesc2 });
        return error.BufferDescriptionsDontMatch;
    }
}

fn compareTexDesc(texEnum1: TextureEnum, texDesc1: *const TexDesc, texEnum2: TextureEnum, texDesc2: *const TexDesc) !void {
    const equal = if (std.meta.eql(texDesc1.*, texDesc2.*)) true else false;

    if (equal == false) {
        std.debug.print("ERROR: ResourceMapperSys: Texture Descriptions dont match \n({s}:{})\n({s}:{})\n", .{ @tagName(texEnum1), texDesc1, @tagName(texEnum2), texDesc2 });
        return error.BufferDescriptionsDontMatch;
    }
}

