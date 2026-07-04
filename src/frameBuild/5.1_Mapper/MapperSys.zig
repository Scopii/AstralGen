const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const PassLifetime = @import("../../frameBuild/components.zig").PassLifetime;
const TextureGroup = @import("../../frameBuild/components.zig").TextureGroup;
const BufferGroup = @import("../../frameBuild/components.zig").BufferGroup;
const TextureLink = @import("../../frameBuild/components.zig").TextureLink;
const BufferLink = @import("../../frameBuild/components.zig").BufferLink;
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
            if (mapperData.bufPassIds.isKeyUsed(bufAccess.input) == false) mapperData.bufPassIds.insert(bufAccess.input, bufAccess.input);

            if (bufAccess.output) |bufOutput| {
                if (mapperData.bufPassIds.isKeyUsed(bufOutput) == false) mapperData.bufPassIds.insert(bufOutput, bufOutput);
                try mapperData.linkedBuffers.append(BufferLink{ .in = bufAccess.input, .out = bufAccess.output }); // moved inside, only append when output exists
            }
        }

        while (mapperData.bufPassIds.getLength() > 0) {
            const lastBuf = mapperData.bufPassIds.getLast();
            mapperData.bufPassIds.removeLast();
            mapperData.sharedBuffers.upsert(lastBuf, lastBuf); // seed directly into allSharedBuffers

            var readIndex: u32 = 0;
            while (readIndex < mapperData.sharedBuffers.getLength()) {
                const sharedBuf = mapperData.sharedBuffers.getByIndex(readIndex);
                readIndex += 1;

                const linkedBufLen = mapperData.linkedBuffers.len;
                for (0..linkedBufLen) |linkedIndex| {
                    const curIndex = linkedBufLen - linkedIndex - 1;
                    const bufLink = mapperData.linkedBuffers.constSlice()[curIndex];

                    var isShared = false;
                    if (bufLink.in == sharedBuf) isShared = true;
                    if (bufLink.out != null and bufLink.out.? == sharedBuf) isShared = true;

                    if (isShared) {
                        if (mapperData.sharedBuffers.isKeyUsed(bufLink.in) == false) {
                            mapperData.sharedBuffers.upsert(bufLink.in, bufLink.in); // directly into allSharedBuffers
                            mapperData.bufPassIds.remove(bufLink.in);
                        }
                        if (bufLink.out) |out| {
                            if (mapperData.sharedBuffers.isKeyUsed(out) == false) {
                                mapperData.sharedBuffers.upsert(out, out); // directly into allSharedBuffers
                                mapperData.bufPassIds.remove(out);
                            }
                        }
                        mapperData.linkedBuffers.swapRemove(@intCast(curIndex));
                    }
                }
            }

            // Resolve All Buffers For Validation, Move all to correct Map
            var lastBufPassId: BufPassId = undefined;
            var lastBufDescription: ?BufDesc = null;

            var lastLifetime: ?PassLifetime = null;
            var rootBuf: BufPassId = undefined;

            for (mapperData.sharedBuffers.getConstItems()) |bufPassId| {
                var newBufDesc = resourceData.bufDescs.getByKey(bufPassId);

                if (lastBufDescription) |lastBufDesc| {
                    newBufDesc = try compareBufDesc(lastBufPassId, &lastBufDesc, bufPassId, &newBufDesc, registryData);
                }

                // Check Root Lifetime
                const newLifetime = lifetimeData.bufLifetimes.getByKey(bufPassId);

                if (lastLifetime) |last| {
                    if (newLifetime.earliest < last.earliest or (newLifetime.earliest == last.earliest and newLifetime.latest < last.latest)) {
                        lastLifetime = newLifetime;
                        rootBuf = bufPassId;
                    }
                } else {
                    rootBuf = bufPassId;
                    lastLifetime = newLifetime;
                }

                lastBufPassId = bufPassId;
                lastBufDescription = newBufDesc;
            }

            // Create Root Mapping
            for (mapperData.sharedBuffers.getConstItems()) |bufPassId| {
                switch (lastBufDescription.?.share) {
                    .transient => mapperData.bufMapTransient.upsert(bufPassId, rootBuf),
                    .persistent => mapperData.bufMapPersistent.upsert(bufPassId, rootBuf),
                }
            }

            // Create Group
            switch (lastBufDescription.?.share) {
                .transient => {
                    const bufGroup = BufferGroup{
                        .rootPass = optimizerData.optimizedGraph.getConstItems()[lastLifetime.?.earliest].pass,
                        .bufDesc = lastBufDescription.?,
                        .firstMapIndex = @intCast(mapperData.bufMapTransient.getLength() - mapperData.sharedBuffers.getLength()),
                        .lastMapIndex = @intCast(mapperData.bufMapTransient.getLength() - 1),
                    };
                    mapperData.bufGroupsTransient.upsert(rootBuf, bufGroup);
                },
                .persistent => {
                    const bufGroup = BufferGroup{
                        .rootPass = optimizerData.optimizedGraph.getConstItems()[lastLifetime.?.earliest].pass,
                        .bufDesc = lastBufDescription.?,
                        .firstMapIndex = @intCast(mapperData.bufMapPersistent.getLength() - mapperData.sharedBuffers.getLength()),
                        .lastMapIndex = @intCast(mapperData.bufMapPersistent.getLength() - 1),
                    };
                    mapperData.bufGroupsPersistent.upsert(rootBuf, bufGroup);
                },
            }
            mapperData.sharedBuffers.clear();
        }

        // Textures
        for (accessData.texAccesses.constSlice()) |texAccess| {
            if (mapperData.texPassIds.isKeyUsed(texAccess.input) == false) mapperData.texPassIds.insert(texAccess.input, texAccess.input);

            if (texAccess.output) |texOutput| {
                if (mapperData.texPassIds.isKeyUsed(texOutput) == false) mapperData.texPassIds.insert(texOutput, texOutput);
                try mapperData.linkedTextures.append(TextureLink{ .in = texAccess.input, .out = texAccess.output }); // moved inside, only append when output exists
            }
        }

        while (mapperData.texPassIds.getLength() > 0) {
            const lastTex = mapperData.texPassIds.getLast();
            mapperData.texPassIds.removeLast();
            mapperData.sharedTextures.upsert(lastTex, lastTex); // seed directly into allSharedTextures

            var readIndex: u32 = 0;
            while (readIndex < mapperData.sharedTextures.getLength()) {
                const sharedTex = mapperData.sharedTextures.getByIndex(readIndex);
                readIndex += 1;

                const linkedTexLen = mapperData.linkedTextures.len;
                for (0..linkedTexLen) |linkedIndex| {
                    const curIndex = linkedTexLen - linkedIndex - 1;
                    const texLink = mapperData.linkedTextures.constSlice()[curIndex];

                    var isShared = false;
                    if (texLink.in == sharedTex) isShared = true;
                    if (texLink.out != null and texLink.out.? == sharedTex) isShared = true;

                    if (isShared) {
                        if (mapperData.sharedTextures.isKeyUsed(texLink.in) == false) {
                            mapperData.sharedTextures.upsert(texLink.in, texLink.in); // directly into allSharedTextures
                            mapperData.texPassIds.remove(texLink.in);
                        }
                        if (texLink.out) |out| {
                            if (mapperData.sharedTextures.isKeyUsed(out) == false) {
                                mapperData.sharedTextures.upsert(out, out); // directly into allSharedTextures
                                mapperData.texPassIds.remove(out);
                            }
                        }
                        mapperData.linkedTextures.swapRemove(@intCast(curIndex));
                    }
                }
            }

            var lastTexPassId: TexPassId = undefined;
            var lastTexDescription: ?TexDesc = null;

            var lastLifetime: ?PassLifetime = null;
            var rootTex: TexPassId = undefined;

            for (mapperData.sharedTextures.getConstItems()) |texPassId| {
                var newTexDesc = resourceData.texDescs.getByKey(texPassId);

                if (lastTexDescription) |lastTexDesc| {
                    newTexDesc = try compareTexDesc(lastTexPassId, &lastTexDesc, texPassId, &newTexDesc, registryData);
                }

                // Check Root Lifetime
                const newLifetime = lifetimeData.texLifetimes.getByKey(texPassId);

                if (lastLifetime) |last| {
                    if (newLifetime.earliest < last.earliest or (newLifetime.earliest == last.earliest and newLifetime.latest < last.latest)) {
                        lastLifetime = newLifetime;
                        rootTex = texPassId;
                    }
                } else {
                    rootTex = texPassId;
                    lastLifetime = newLifetime;
                }

                lastTexPassId = texPassId;
                lastTexDescription = newTexDesc;
            }

            // Root Mappings
            for (mapperData.sharedTextures.getConstItems()) |texPassId| {
                switch (lastTexDescription.?.share) {
                    .transient => mapperData.texMapTransient.upsert(texPassId, rootTex),
                    .persistent => mapperData.texMapPersistent.upsert(texPassId, rootTex),
                }
            }

            // Create Group
            switch (lastTexDescription.?.share) {
                .transient => {
                    const texGroup = TextureGroup{
                        .rootPass = optimizerData.optimizedGraph.getConstItems()[lastLifetime.?.earliest].pass,
                        .texDesc = lastTexDescription.?,
                        .firstMapIndex = @intCast(mapperData.texMapTransient.getLength() - mapperData.sharedTextures.getLength()),
                        .lastMapIndex = @intCast(mapperData.texMapTransient.getLength() - 1),
                    };
                    mapperData.texGroupsTransient.upsert(rootTex, texGroup);
                },
                .persistent => {
                    const texGroup = TextureGroup{
                        .rootPass = optimizerData.optimizedGraph.getConstItems()[lastLifetime.?.earliest].pass,
                        .texDesc = lastTexDescription.?,
                        .firstMapIndex = @intCast(mapperData.texMapPersistent.getLength() - mapperData.sharedTextures.getLength()),
                        .lastMapIndex = @intCast(mapperData.texMapPersistent.getLength() - 1),
                    };
                    mapperData.texGroupsPersistent.upsert(rootTex, texGroup);
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
                const rootBufPassId = mapperData.lastBufGroupsPersistent.getKeyByIndex(@intCast(i));
                const rootBuf = try registryData.getBufferName(rootBufPassId);
                const rootPass = try registryData.getPassName(group.rootPass);
                std.debug.print("BufGroup (Persistent {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootBuf, rootPass, group.firstMapIndex, group.lastMapIndex });
            }

            for (mapperData.lastBufGroupsTransient.getConstItems(), 0..) |group, i| {
                const rootBufPassId = mapperData.lastBufGroupsTransient.getKeyByIndex(@intCast(i));
                const rootBuf = try registryData.getBufferName(rootBufPassId);
                const rootPass = try registryData.getPassName(group.rootPass);
                std.debug.print("BufGroup (Transient {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootBuf, rootPass, group.firstMapIndex, group.lastMapIndex });
            }

            // Group Debug Textures
            for (mapperData.lastTexGroupsPersistent.getConstItems(), 0..) |group, i| {
                const rootTexPassId = mapperData.lastTexGroupsPersistent.getKeyByIndex(@intCast(i));
                const rootTex = try registryData.getTextureName(rootTexPassId);
                const rootPass = try registryData.getPassName(group.rootPass);
                std.debug.print("TexGroup (Persistent {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootTex, rootPass, group.firstMapIndex, group.lastMapIndex });
            }

            for (mapperData.lastTexGroupsTransient.getConstItems(), 0..) |group, i| {
                const rootTexPassId = mapperData.lastTexGroupsTransient.getKeyByIndex(@intCast(i));
                const rootTex = try registryData.getTextureName(rootTexPassId);
                const rootPass = try registryData.getPassName(group.rootPass);
                std.debug.print("TexGroup (Transient {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootTex, rootPass, group.firstMapIndex, group.lastMapIndex });
            }

            std.debug.print("\n", .{});
            std.debug.print("Current: \n", .{});

            // Group Debug Buffers
            for (mapperData.bufGroupsPersistent.getConstItems(), 0..) |group, i| {
                const rootBufPassId = mapperData.bufGroupsPersistent.getKeyByIndex(@intCast(i));
                const rootBuf = try registryData.getBufferName(rootBufPassId);
                const rootPass = try registryData.getPassName(group.rootPass);
                std.debug.print("BufGroup (Persistent {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootBuf, rootPass, group.firstMapIndex, group.lastMapIndex });

                for (group.firstMapIndex..group.lastMapIndex + 1, 0..) |mapIndex, counter| {
                    const bufPassId = mapperData.bufMapPersistent.getKeyByIndex(@intCast(mapIndex));
                    const bufName = try registryData.getBufferName(bufPassId);
                    std.debug.print("     -> {}. {s}\n", .{ counter, bufName });
                }
            }

            for (mapperData.bufGroupsTransient.getConstItems(), 0..) |group, i| {
                const rootBufPassId = mapperData.bufGroupsTransient.getKeyByIndex(@intCast(i));
                const rootBuf = try registryData.getBufferName(rootBufPassId);
                const rootPass = try registryData.getPassName(group.rootPass);
                std.debug.print("BufGroup (Transient {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootBuf, rootPass, group.firstMapIndex, group.lastMapIndex });

                for (group.firstMapIndex..group.lastMapIndex + 1, 0..) |mapIndex, counter| {
                    const bufPassId = mapperData.bufMapTransient.getKeyByIndex(@intCast(mapIndex));
                    const bufName = try registryData.getBufferName(bufPassId);
                    std.debug.print("     -> {}. {s}\n", .{ counter, bufName });
                }
            }

            // Group Debug Textures
            for (mapperData.texGroupsPersistent.getConstItems(), 0..) |group, i| {
                const rootTexPassId = mapperData.texGroupsPersistent.getKeyByIndex(@intCast(i));
                const rootTex = try registryData.getTextureName(rootTexPassId);
                const rootPass = try registryData.getPassName(group.rootPass);
                std.debug.print("TexGroup (Persistent {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootTex, rootPass, group.firstMapIndex, group.lastMapIndex });

                for (group.firstMapIndex..group.lastMapIndex + 1, 0..) |mapIndex, counter| {
                    const texPassId = mapperData.texMapPersistent.getKeyByIndex(@intCast(mapIndex));
                    const texName = try registryData.getTextureName(texPassId);
                    std.debug.print("     -> {}. {s}\n", .{ counter, texName });
                }
            }

            for (mapperData.texGroupsTransient.getConstItems(), 0..) |group, i| {
                const rootTexPassId = mapperData.texGroupsTransient.getKeyByIndex(@intCast(i));
                const rootTex = try registryData.getTextureName(rootTexPassId);
                const rootPass = try registryData.getPassName(group.rootPass);
                std.debug.print("TexGroup (Transient {}) (RootRes {s}) (RootPass {s}) (mapIndex {} -> {})\n", .{ i, rootTex, rootPass, group.firstMapIndex, group.lastMapIndex });

                for (group.firstMapIndex..group.lastMapIndex + 1, 0..) |mapIndex, counter| {
                    const texPassId = mapperData.texMapTransient.getKeyByIndex(@intCast(mapIndex));
                    const texName = try registryData.getTextureName(texPassId);
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
