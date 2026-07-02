const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const TextureLifetime = @import("../../frameBuild/components.zig").TextureLifetime;
const BufferLifetime = @import("../../frameBuild/components.zig").BufferLifetime;
const TextureGroup = @import("../../frameBuild/components.zig").TextureGroup;
const BufferGroup = @import("../../frameBuild/components.zig").BufferGroup;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const ResourceData = @import("../2_Resource/ResourceData.zig").ResourceData;
const OptimizerData = @import("../4.5_Optimizer/OptimizerData.zig").OptimizerData;
const LifetimeData = @import("../5_Lifetime/LifetimeData.zig").LifetimeData;
const MapperData = @import("MapperData.zig").MapperData;
const AccessData = @import("../1.5_Access/AccessData.zig").AccessData;

// Step 5.1

pub const MapperSys = struct {
    pub fn buildMapping(
        mapperData: *MapperData,
        accessData: *const AccessData,
        resourceData: *const ResourceData,
        lifetimeData: *const LifetimeData,
        optimizerData: *const OptimizerData,
        registryData: *const RegistryData,
    ) !void {
        // Move Last Mapping and Clear current
        mapperData.bufMapTransient.clear();
        mapperData.bufMapPersistent.clear();
        mapperData.texMapTransient.clear();
        mapperData.texMapPersistent.clear();

        mapperData.lastBufGroupsTransient = mapperData.bufGroupsTransient;
        mapperData.lastBufGroupsPersistent = mapperData.bufGroupsPersistent;
        mapperData.lastTexGroupsTransient = mapperData.texGroupsTransient;
        mapperData.lastTexGroupsPersistent = mapperData.texGroupsPersistent;

        mapperData.bufGroupsTransient.clear();
        mapperData.bufGroupsPersistent.clear();
        mapperData.texGroupsTransient.clear();
        mapperData.texGroupsPersistent.clear();

        // Buffer

        for (accessData.bufAccesses.constSlice()) |bufAccess| {
            const bufInputKey: u16 = bufAccess.bufInput.val();
            if (mapperData.bufPassIds.isKeyUsed(bufInputKey) == false) mapperData.bufPassIds.insert(bufInputKey, bufAccess.bufInput);

            if (bufAccess.bufOutput) |bufOutput| {
                const bufOutputKey: u16 = bufOutput.val();
                if (mapperData.bufPassIds.isKeyUsed(bufOutputKey) == false) mapperData.bufPassIds.insert(bufOutputKey, bufOutput);
                try mapperData.linkedBuffers.append(.{ .in = bufAccess.bufInput, .out = bufAccess.bufOutput }); // moved inside — only append when output exists
            }
        }

        while (mapperData.bufPassIds.getLength() > 0) {
            const lastBuf = mapperData.bufPassIds.getLast();
            mapperData.bufPassIds.removeLast();
            mapperData.sharedBuffers.upsert(lastBuf.val(), lastBuf); // seed directly into allSharedBuffers

            var readIndex: u32 = 0;
            while (readIndex < mapperData.sharedBuffers.getLength()) {
                const sharedBuf = mapperData.sharedBuffers.getByIndex(readIndex);
                readIndex += 1;

                const linkedBufLen = mapperData.linkedBuffers.len;
                for (0..linkedBufLen) |linkedIndex| {
                    const curIndex = linkedBufLen - linkedIndex - 1;
                    const bufLink = mapperData.linkedBuffers.constSlice()[curIndex];

                    var isShared = false;
                    if (bufLink.in.val() == sharedBuf.val()) isShared = true;
                    if (bufLink.out != null and bufLink.out.?.val() == sharedBuf.val()) isShared = true;

                    if (isShared) {
                        if (mapperData.sharedBuffers.isKeyUsed(bufLink.in.val()) == false) {
                            mapperData.sharedBuffers.upsert(bufLink.in.val(), bufLink.in); // directly into allSharedBuffers
                            mapperData.bufPassIds.remove(bufLink.in.val());
                        }
                        if (bufLink.out) |out| {
                            if (mapperData.sharedBuffers.isKeyUsed(out.val()) == false) {
                                mapperData.sharedBuffers.upsert(out.val(), out); // directly into allSharedBuffers
                                mapperData.bufPassIds.remove(out.val());
                            }
                        }
                        mapperData.linkedBuffers.swapRemove(@intCast(curIndex));
                    }
                }
            }

            // Resolve All Buffers For Validation, Move all to correct Map
            var lastBufPassId: BufPassId = undefined;
            var lastBufDescription: ?BufDesc = null;

            var lastLifetime: ?BufferLifetime = null;
            var root: BufPassId = undefined;

            for (mapperData.sharedBuffers.getConstItems()) |bufPassId| {
                var newBufDesc = resourceData.bufDescs.getByKey(bufPassId.val());

                if (lastBufDescription) |lastBufDesc| {
                    newBufDesc = try compareBufDesc(lastBufPassId, &lastBufDesc, bufPassId, &newBufDesc, registryData);
                }

                // Check Root Lifetime
                const newLifetime = lifetimeData.bufLifetimes.getByKey(bufPassId.val());

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
            for (mapperData.sharedBuffers.getConstItems()) |bufPassId| {
                switch (lastBufDescription.?.share) {
                    .transient => mapperData.bufMapTransient.upsert(bufPassId.val(), root),
                    .persistent => mapperData.bufMapPersistent.upsert(bufPassId.val(), root),
                }
            }

            // Create Group
            switch (lastBufDescription.?.share) {
                .transient => {
                    const bufGroup = BufferGroup{
                        .rootPass = optimizerData.optimizedGraph.getConstItems()[lastLifetime.?.earliest].pass,
                        .rootBuf = root,
                        .bufDesc = lastBufDescription.?,
                        .firstMapIndex = @intCast(mapperData.bufMapTransient.getLength() - mapperData.sharedBuffers.getLength()),
                        .lastMapIndex = @intCast(mapperData.bufMapTransient.getLength() - 1),
                    };
                    mapperData.bufGroupsTransient.upsert(root.val(), bufGroup);
                },
                .persistent => {
                    const bufGroup = BufferGroup{
                        .rootPass = optimizerData.optimizedGraph.getConstItems()[lastLifetime.?.earliest].pass,
                        .rootBuf = root,
                        .bufDesc = lastBufDescription.?,
                        .firstMapIndex = @intCast(mapperData.bufMapPersistent.getLength() - mapperData.sharedBuffers.getLength()),
                        .lastMapIndex = @intCast(mapperData.bufMapPersistent.getLength() - 1),
                    };
                    mapperData.bufGroupsPersistent.upsert(root.val(), bufGroup);
                },
            }
            mapperData.sharedBuffers.clear();
        }

        // Textures
        for (accessData.texAccesses.constSlice()) |texAccess| {
            const texInputKey: u16 = texAccess.texInput.val();
            if (mapperData.texPassIds.isKeyUsed(texInputKey) == false) mapperData.texPassIds.insert(texInputKey, texAccess.texInput);

            if (texAccess.texOutput) |texOutput| {
                const texOutputKey: u16 = texOutput.val();
                if (mapperData.texPassIds.isKeyUsed(texOutputKey) == false) mapperData.texPassIds.insert(texOutputKey, texOutput);
                try mapperData.linkedTextures.append(.{ .in = texAccess.texInput, .out = texAccess.texOutput }); // moved inside — only append when output exists
            }
        }

        while (mapperData.texPassIds.getLength() > 0) {
            const lastTex = mapperData.texPassIds.getLast();
            mapperData.texPassIds.removeLast();
            mapperData.sharedTextures.upsert(lastTex.val(), lastTex); // seed directly into allSharedTextures

            var readIndex: u32 = 0;
            while (readIndex < mapperData.sharedTextures.getLength()) {
                const sharedTex = mapperData.sharedTextures.getByIndex(readIndex);
                readIndex += 1;

                const linkedTexLen = mapperData.linkedTextures.len;
                for (0..linkedTexLen) |linkedIndex| {
                    const curIndex = linkedTexLen - linkedIndex - 1;
                    const texLink = mapperData.linkedTextures.constSlice()[curIndex];

                    var isShared = false;
                    if (texLink.in.val() == sharedTex.val()) isShared = true;
                    if (texLink.out != null and texLink.out.?.val() == sharedTex.val()) isShared = true;

                    if (isShared) {
                        if (mapperData.sharedTextures.isKeyUsed(texLink.in.val()) == false) {
                            mapperData.sharedTextures.upsert(texLink.in.val(), texLink.in); // directly into allSharedTextures
                            mapperData.texPassIds.remove(texLink.in.val());
                        }
                        if (texLink.out) |out| {
                            if (mapperData.sharedTextures.isKeyUsed(out.val()) == false) {
                                mapperData.sharedTextures.upsert(out.val(), out); // directly into allSharedTextures
                                mapperData.texPassIds.remove(out.val());
                            }
                        }
                        mapperData.linkedTextures.swapRemove(@intCast(curIndex));
                    }
                }
            }

            var lastTexPassId: TexPassId = undefined;
            var lastTexDescription: ?TexDesc = null;

            var lastLifetime: ?TextureLifetime = null;
            var root: TexPassId = undefined;

            for (mapperData.sharedTextures.getConstItems()) |texPassId| {
                var newTexDesc = resourceData.texDescs.getByKey(texPassId.val());

                if (lastTexDescription) |lastTexDesc| {
                    newTexDesc = try compareTexDesc(lastTexPassId, &lastTexDesc, texPassId, &newTexDesc, registryData);
                }

                // Check Root Lifetime
                const newLifetime = lifetimeData.texLifetimes.getByKey(texPassId.val());

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
            for (mapperData.sharedTextures.getConstItems()) |texPassId| {
                switch (lastTexDescription.?.share) {
                    .transient => mapperData.texMapTransient.upsert(texPassId.val(), root),
                    .persistent => mapperData.texMapPersistent.upsert(texPassId.val(), root),
                }
            }

            // Create Group
            switch (lastTexDescription.?.share) {
                .transient => {
                    const texGroup = TextureGroup{
                        .rootPass = optimizerData.optimizedGraph.getConstItems()[lastLifetime.?.earliest].pass,
                        .rootTex = root,
                        .texDesc = lastTexDescription.?,
                        .firstMapIndex = @intCast(mapperData.texMapTransient.getLength() - mapperData.sharedTextures.getLength()),
                        .lastMapIndex = @intCast(mapperData.texMapTransient.getLength() - 1),
                    };
                    mapperData.texGroupsTransient.upsert(root.val(), texGroup);
                },
                .persistent => {
                    const texGroup = TextureGroup{
                        .rootPass = optimizerData.optimizedGraph.getConstItems()[lastLifetime.?.earliest].pass,
                        .rootTex = root,
                        .texDesc = lastTexDescription.?,
                        .firstMapIndex = @intCast(mapperData.texMapPersistent.getLength() - mapperData.sharedTextures.getLength()),
                        .lastMapIndex = @intCast(mapperData.texMapPersistent.getLength() - 1),
                    };
                    mapperData.texGroupsPersistent.upsert(root.val(), texGroup);
                },
            }

            mapperData.sharedTextures.clear();
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.1.ResourceMapper: \n", .{});

            std.debug.print("Previous: \n", .{});
            // Buffer Debug
            for (mapperData.lastBufGroupsPersistent.getConstItems(), 0..) |group, i| {
                const rootBuf = try registryData.getBufferName(group.rootBuf);
                const rootPass = try registryData.getPassName(group.rootPass);
                std.debug.print("BufGroup (Persistent {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootBuf, rootPass, group.firstMapIndex, group.lastMapIndex });
            }

            for (mapperData.lastBufGroupsTransient.getConstItems(), 0..) |group, i| {
                const rootBuf = try registryData.getBufferName(group.rootBuf);
                const rootPass = try registryData.getPassName(group.rootPass);
                std.debug.print("BufGroup (Transient {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootBuf, rootPass, group.firstMapIndex, group.lastMapIndex });
            }

            // Group Debug Textures
            for (mapperData.lastTexGroupsPersistent.getConstItems(), 0..) |group, i| {
                const rootTex = try registryData.getTextureName(group.rootTex);
                const rootPass = try registryData.getPassName(group.rootPass);
                std.debug.print("TexGroup (Persistent {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootTex, rootPass, group.firstMapIndex, group.lastMapIndex });
            }

            for (mapperData.lastTexGroupsTransient.getConstItems(), 0..) |group, i| {
                const rootTex = try registryData.getTextureName(group.rootTex);
                const rootPass = try registryData.getPassName(group.rootPass);
                std.debug.print("TexGroup (Transient {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootTex, rootPass, group.firstMapIndex, group.lastMapIndex });
            }

            std.debug.print("\n", .{});
            std.debug.print("Current: \n", .{});

            // Group Debug Buffers
            for (mapperData.bufGroupsPersistent.getConstItems(), 0..) |group, i| {
                const rootBuf = try registryData.getBufferName(group.rootBuf);
                const rootPass = try registryData.getPassName(group.rootPass);
                std.debug.print("BufGroup (Persistent {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootBuf, rootPass, group.firstMapIndex, group.lastMapIndex });

                for (group.firstMapIndex..group.lastMapIndex + 1, 0..) |mapIndex, counter| {
                    const bufKey: u16 = mapperData.bufMapPersistent.getKeyByIndex(@intCast(mapIndex));
                    const bufName = try registryData.getBufferName(.id(bufKey));
                    std.debug.print("     -> {}. {s}\n", .{ counter, bufName });
                }
            }

            for (mapperData.bufGroupsTransient.getConstItems(), 0..) |group, i| {
                const rootBuf = try registryData.getBufferName(group.rootBuf);
                const rootPass = try registryData.getPassName(group.rootPass);
                std.debug.print("BufGroup (Transient {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootBuf, rootPass, group.firstMapIndex, group.lastMapIndex });

                for (group.firstMapIndex..group.lastMapIndex + 1, 0..) |mapIndex, counter| {
                    const bufKey: u16 = mapperData.bufMapTransient.getKeyByIndex(@intCast(mapIndex));
                    const bufName = try registryData.getBufferName(.id(bufKey));
                    std.debug.print("     -> {}. {s}\n", .{ counter, bufName });
                }
            }

            // Group Debug Textures
            for (mapperData.texGroupsPersistent.getConstItems(), 0..) |group, i| {
                const rootTex = try registryData.getTextureName(group.rootTex);
                const rootPass = try registryData.getPassName(group.rootPass);
                std.debug.print("TexGroup (Persistent {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootTex, rootPass, group.firstMapIndex, group.lastMapIndex });

                for (group.firstMapIndex..group.lastMapIndex + 1, 0..) |mapIndex, counter| {
                    const texKey: u16 = mapperData.texMapPersistent.getKeyByIndex(@intCast(mapIndex));
                    const texName = try registryData.getTextureName(.id(texKey));
                    std.debug.print("     -> {}. {s}\n", .{ counter, texName });
                }
            }

            for (mapperData.texGroupsTransient.getConstItems(), 0..) |group, i| {
                const rootTex = try registryData.getTextureName(group.rootTex);
                const rootPass = try registryData.getPassName(group.rootPass);
                std.debug.print("TexGroup (Transient {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootTex, rootPass, group.firstMapIndex, group.lastMapIndex });

                for (group.firstMapIndex..group.lastMapIndex + 1, 0..) |mapIndex, counter| {
                    const texKey: u16 = mapperData.texMapTransient.getKeyByIndex(@intCast(mapIndex));
                    const texName = try registryData.getTextureName(.id(texKey));
                    std.debug.print("     -> {}. {s}\n", .{ counter, texName });
                }
            }

            std.debug.print("\n", .{});
        }
    }
};

fn compareBufDesc(bufId1: BufPassId, bufDesc1: *const BufDesc, bufId2: BufPassId, bufDesc2: *const BufDesc, registryData: *const RegistryData) !BufDesc {
    const equal = if (std.meta.eql(bufDesc1.*, bufDesc2.*)) true else false;

    if (equal == false) {
        const bufName1 = try registryData.getBufferName(bufId1);
        const bufName2 = try registryData.getBufferName(bufId2);
        std.debug.print("ERROR: ResourceMapperSys: Buffer Descriptions dont match \n({s}:{})\n({s}:{})\n", .{ bufName1, bufDesc1, bufName2, bufDesc2 });
        return error.BufferDescriptionsDontMatch;
    }

    return bufDesc1.*;
}

fn compareTexDesc(texId1: TexPassId, texDesc1: *const TexDesc, texId2: TexPassId, texDesc2: *const TexDesc, registryData: *const RegistryData) !TexDesc {
    // const equal = if (std.meta.eql(texDesc1.*, texDesc2.*)) true else false;

    const equal = if (texDesc1.share == texDesc2.share and
        texDesc1.mem == texDesc2.mem and
        texDesc1.typ == texDesc2.typ and
        texDesc1.texUse == texDesc2.texUse and
        texDesc1.descriptors == texDesc2.descriptors and
        // texDesc1.width == texDesc2.width and
        // texDesc1.height == texDesc2.height and
        texDesc1.depth == texDesc2.depth and
        texDesc1.update == texDesc2.update and
        texDesc1.resize == texDesc2.resize and
        texDesc1.fitPass == texDesc2.fitPass)
        true
    else
        false;

    const maxWidth = @max(texDesc1.width, texDesc2.width);
    const maxHeight = @max(texDesc1.height, texDesc2.height);

    if (equal == false) {
        const texName1 = try registryData.getTextureName(texId1);
        const texName2 = try registryData.getTextureName(texId2);
        std.debug.print("ERROR: ResourceMapperSys: Texture Descriptions dont match \n({s}:{})\n({s}:{})\n", .{ texName1, texDesc1, texName2, texDesc2 });
        return error.TextureDescriptionsDontMatch;
    }

    return TexDesc{
        .share = texDesc1.share,
        .mem = texDesc1.mem,
        .typ = texDesc1.typ,
        .texUse = texDesc1.texUse,
        .descriptors = texDesc1.descriptors,
        .depth = texDesc1.depth,
        .width = maxWidth,
        .height = maxHeight,
        .update = texDesc1.update,
        .resize = texDesc1.resize,
        .fitPass = texDesc1.fitPass,
    };
}
