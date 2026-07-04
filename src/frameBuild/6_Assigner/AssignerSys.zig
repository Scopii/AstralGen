const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const TransientTexture = @import("../../frameBuild/components.zig").TransientTexture;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const TransientBuffer = @import("../../frameBuild/components.zig").TransientBuffer;
const TextureMeta = @import("../../render/types/res/TextureMeta.zig").TextureMeta;
const BufferMeta = @import("../../render/types/res/BufferMeta.zig").BufferMeta;
const RendererQueue = @import("../../render/RendererQueue.zig").RendererQueue;
const MemoryManager = @import("../../core/MemoryManager.zig").MemoryManager;
const TexId = @import("../../.configs/idConfig.zig").TexId;
const BufId = @import("../../.configs/idConfig.zig").BufId;
const rc = @import("../../.configs/renderConfig.zig");
const pe = @import("../enums.zig");
const std = @import("std");

const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const MapperData = @import("../5.1_Mapper/MapperData.zig").MapperData;
const ComparatorData = @import("../5.3_Comparator/ComparatorData.zig").ComparatorData;
const GroupData = @import("../5.4_Group/GroupData.zig").GroupData;
const AssignerData = @import("AssignerData.zig").AssignerData;

const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const TexInf = TextureMeta.TexInf;
const BufInf = BufferMeta.BufInf;

// WHAT ABOUT INDIRECT DEPENDENCIES? (SPLITTING INTO OUTPUT PASSES AND ALL PASSES? SPLITTING GLOBAL PASSES AND INSTANCE PASSES?)

// Step 6

pub const AssignerSys = struct {
    pub fn buildPersistentResources(
        assignerData: *AssignerData,
        mapperData: *const MapperData,
        comparatorData: *const ComparatorData,
        groupData: *const GroupData,
        registryData: *const RegistryData,
        rendererQueue: *RendererQueue,
        memoryMan: *MemoryManager,
    ) !void {
        // Resets
        assignerData.updateRequests.clear();
        assignerData.bufAssigns.clear();
        assignerData.texAssigns.clear();

        const usedBuffers = assignerData.usedTransientBufs.constSlice();
        assignerData.unusedTransientBufs.appendSlice(usedBuffers) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to unusedTransientBufs\n", .{});
        assignerData.usedTransientBufs.clear();

        const usedTextures = assignerData.usedTransientTexes.constSlice();
        assignerData.unusedTransientTexes.appendSlice(usedTextures) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to unusedTransientTexes\n", .{});
        assignerData.usedTransientTexes.clear();

        // TRANSIENT RESOURCES //

        // Check needed Shared Lifetimes to create or re-use existing Physical Buffer
        for (groupData.sharedBufLifetimes.constSlice()) |sharedBufLifetime| {
            var physCandidateIndex: ?u16 = null;
            const sharedBufDesc = mapperData.bufGroupsTransient.getByKey(sharedBufLifetime.bufDescId).bufDesc;

            for (assignerData.unusedTransientBufs.constSlice(), 0..) |transientBuf, i| {
                // Check if Desc Fits Existing Info
                if (bufDescEqual(&transientBuf.bufDesc, &sharedBufDesc) == true) {
                    physCandidateIndex = @intCast(i);
                    break;
                }
            }

            if (physCandidateIndex) |candidateIndex| {
                // Candidate was found -> move from unused ot used List
                var candidate = assignerData.unusedTransientBufs.swapRemoveReturn(candidateIndex);
                candidate.unusedCounter = 0;
                assignerData.usedTransientBufs.append(candidate) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientBufs\n", .{});
            } else {
                // Candidate not found -> create new
                const candidate = TransientBuffer{ .bufDesc = sharedBufDesc, .hardwareBuf = try getFreeBufId(assignerData) };
                try createTransientBuffer(sharedBufDesc, candidate.hardwareBuf, rendererQueue, memoryMan);
                assignerData.usedTransientBufs.append(candidate) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientBufs\n", .{});
            }
        }

        // Increment unused, delete all larger than Constant
        const unusedTransientBufsLen = assignerData.unusedTransientBufs.len;

        for (0..unusedTransientBufsLen) |i| {
            const index = unusedTransientBufsLen - 1 - i;
            const transientBuf = &assignerData.unusedTransientBufs.buffer[index];

            if (transientBuf.unusedCounter >= rc.FRAME_BUILDS_TILL_TRANSIENT_DELETION) {
                deleteTransientBuffer(transientBuf.hardwareBuf, rendererQueue);
                assignerData.unusedTransientBufs.swapRemove(@intCast(index));
                freeUpBufId(assignerData, transientBuf.hardwareBuf);
            } else transientBuf.unusedCounter += 1;
        }

        // Assign Shared Transient Lifetimes to Buffers
        for (groupData.bufShareIndexMap.getConstItems(), 0..) |sharedIndex, i| {
            const bufRootKey = groupData.bufShareIndexMap.getKeyByIndex(@intCast(i));
            const bufId = assignerData.usedTransientBufs.buffer[sharedIndex].hardwareBuf;

            const bufGroup = mapperData.bufGroupsTransient.getByKey(bufRootKey);
            // Whole Group needs to be assigned
            for (bufGroup.firstMapIndex..bufGroup.lastMapIndex + 1) |mapIndex| {
                const memberKey = mapperData.bufMapTransient.getKeyByIndex(@intCast(mapIndex));

                // Link Buffers Enum To Physical Buf ID
                if (assignerData.bufAssigns.isKeyUsed(memberKey) == true) {
                    const bufName = try registryData.getBufferName(memberKey);
                    std.debug.print("ERROR: 6.ResourceAssigner: Buffer Name {s} already assigned!\n", .{bufName});
                    return error.BufEnumAlreadyAssigned;
                }
                assignerData.bufAssigns.upsert(memberKey, bufId);
            }
        }

        // Check needed Shared Lifetimes to create or re-use existing Physical Textures
        for (groupData.sharedTexLifetimes.constSlice()) |sharedTexLifetime| {
            var physCandidateIndex: ?u16 = null;
            const sharedTexDesc = mapperData.texGroupsTransient.getByKey(sharedTexLifetime.texDescId).texDesc;

            for (assignerData.unusedTransientTexes.constSlice(), 0..) |transientTex, i| {
                // Check if Desc Fits Existing Info
                if (texDescEqual(&transientTex.texDesc, &sharedTexDesc) == true) {
                    physCandidateIndex = @intCast(i);
                    break;
                }
            }

            if (physCandidateIndex) |candidateIndex| {
                // Candidate was found -> move from unused ot used List
                var candidate = assignerData.unusedTransientTexes.swapRemoveReturn(candidateIndex);
                candidate.unusedCounter = 0;
                assignerData.usedTransientTexes.append(candidate) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientTexes\n", .{});
            } else {
                // Candidate not found -> create new
                const candidate = TransientTexture{ .texDesc = sharedTexDesc, .hardwareTex = try getFreeTexId(assignerData) };
                try createTransientTexture(sharedTexDesc, candidate.hardwareTex, rendererQueue, memoryMan);
                assignerData.usedTransientTexes.append(candidate) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientTexes\n", .{});
            }
        }

        // Increment unused, delete all larger than Constant
        const unusedTransientTexesLen = assignerData.unusedTransientTexes.len;

        for (0..unusedTransientTexesLen) |i| {
            const index = unusedTransientTexesLen - 1 - i;
            const transientTex = &assignerData.unusedTransientTexes.buffer[index];

            if (transientTex.unusedCounter >= rc.FRAME_BUILDS_TILL_TRANSIENT_DELETION) {
                deleteTransientTexture(transientTex.hardwareTex, rendererQueue);
                assignerData.unusedTransientTexes.swapRemove(@intCast(index));
                freeUpTexId(assignerData, transientTex.hardwareTex);
            } else transientTex.unusedCounter += 1;
        }

        // Assign Shared Transient Lifetimes to Textures
        for (groupData.texShareIndexMap.getConstItems(), 0..) |sharedIndex, i| {
            const texRootKey = groupData.texShareIndexMap.getKeyByIndex(@intCast(i));
            const texId = assignerData.usedTransientTexes.buffer[sharedIndex].hardwareTex;

            const texGroup = mapperData.texGroupsTransient.getByKey(texRootKey);
            // Whole Group needs to be assigned
            for (texGroup.firstMapIndex..texGroup.lastMapIndex + 1) |mapIndex| {
                const memberKey = mapperData.texMapTransient.getKeyByIndex(@intCast(mapIndex));

                // Link Textures Enum To Physical Tex ID
                if (assignerData.texAssigns.isKeyUsed(memberKey) == true) {
                    const texName = try registryData.getTextureName(memberKey);
                    std.debug.print("ERROR: 6.ResourceAssigner: Texture Name {s} already assigned!\n", .{texName});
                    return error.TexEnumAlreadyAssigned;
                }
                assignerData.texAssigns.upsert(memberKey, texId);
            }
        }

        // PERSISTENT RESOURCES //

        // Creating, Deleting and Recreating Persistent Resources
        for (comparatorData.persistentChanges.constSlice()) |groupChange| {
            switch (groupChange.rootResource) {
                .bufPassId => |rootId| {
                    // Buffers
                    switch (groupChange.change) {
                        .unchanged => {},
                        .deleted => {
                            // deleteBuffer(resourceAssigner, resourceRegistry, bufChanges.rootBuf, rendererQueue, .frameGraph);
                            try deferBufferDeletion(assignerData, rootId);
                        },
                        .created => {
                            try createBuffer(assignerData, mapperData, registryData, rootId, rendererQueue, memoryMan, .frameGraph);
                            resolveBufferUpdateRequest(assignerData, rootId);
                        },
                        .newDesc, .newPass, .newPassAndDesc => {
                            // deleteBuffer(resourceAssigner, resourceRegistry, bufChanges.rootBuf, rendererQueue, .frameGraph);
                            try deferBufferDeletion(assignerData, rootId);
                            try createBuffer(assignerData, mapperData, registryData, rootId, rendererQueue, memoryMan, .frameGraph);
                            resolveBufferUpdateRequest(assignerData, rootId);
                        },
                    }
                },
                .texPassId => |rootId| {
                    // Textures
                    switch (groupChange.change) {
                        .unchanged => {},
                        .deleted => {
                            // deleteTexture(resourceAssigner, resourceRegistry, texChanges.rootTex, rendererQueue, .frameGraph);
                            try deferTextureDeletion(assignerData, rootId);
                        },
                        .created => {
                            try createTexture(assignerData, mapperData, registryData, rootId, rendererQueue, memoryMan, .frameGraph);
                            resolveTextureUpdateRequest(assignerData, rootId);
                        },
                        .newDesc, .newPass, .newPassAndDesc => {
                            // deleteTexture(resourceAssigner, resourceRegistry, texChanges.rootTex, rendererQueue, .frameGraph);
                            try deferTextureDeletion(assignerData, rootId);
                            try createTexture(assignerData, mapperData, registryData, rootId, rendererQueue, memoryMan, .frameGraph);
                            resolveTextureUpdateRequest(assignerData, rootId);
                        },
                    }
                },
            }
        }

        if (rc.FRAME_GRAPH_DEBUG) std.debug.print("\n", .{});

        // Create Manuel Buffer Assignments
        for (assignerData.manualBufs.getConstItems(), 0..) |bufInf, i| {
            const enumKey = assignerData.manualBufs.getKeyByIndex(@intCast(i));
            assignerData.bufAssigns.upsert(enumKey, bufInf.id);
        }

        // Create Persistent Buffer Assignments
        for (mapperData.bufGroupsPersistent.getConstItems(), 0..) |bufGroup, i| {
            const groupRootBuf = mapperData.bufGroupsPersistent.getKeyByIndex(@intCast(i));
            const rootBufPhysicalId = assignerData.rootBufPhysicalMap.getByKey(groupRootBuf);

            for (bufGroup.firstMapIndex..bufGroup.lastMapIndex + 1) |mapIndex| {
                const bufEnumKey = mapperData.bufMapPersistent.getKeyByIndex(@intCast(mapIndex));

                // Link Buffer Pass ID To Physical Buf ID
                if (assignerData.bufAssigns.isKeyUsed(bufEnumKey) == true) {
                    const bufName = try registryData.getBufferName(groupRootBuf);
                    std.debug.print("ERROR: 6.ResourceAssigner: Buffer {s} already assigned!\n", .{bufName});
                    return error.BufEnumAlreadyAssigned;
                }
                assignerData.bufAssigns.upsert(bufEnumKey, rootBufPhysicalId.id);
            }
        }

        // Create Manuel Texture Assignments
        for (assignerData.manualTexes.getConstItems(), 0..) |texInf, i| {
            const texPassId = assignerData.manualTexes.getKeyByIndex(@intCast(i));
            assignerData.texAssigns.upsert(texPassId, texInf.id);
        }

        // Create Persistent Texture Assignment
        for (mapperData.texGroupsPersistent.getConstItems(), 0..) |texGroup, i| {
            const groupRootBuf = mapperData.texGroupsPersistent.getKeyByIndex(@intCast(i));
            const rootTexPhysicalId = assignerData.rootTexPhysicalMap.getByKey(groupRootBuf);

            for (texGroup.firstMapIndex..texGroup.lastMapIndex + 1) |mapIndex| {
                const texKey = mapperData.texMapPersistent.getKeyByIndex(@intCast(mapIndex));

                // Link Texture Pass ID To Physical Tex ID
                if (assignerData.texAssigns.isKeyUsed(texKey) == true) {
                    const texName = try registryData.getTextureName(groupRootBuf);
                    std.debug.print("ERROR: 6.ResourceAssigner: Texture {s} already assigned!\n", .{texName});
                    return error.BufEnumAlreadyAssigned;
                }
                assignerData.texAssigns.upsert(texKey, rootTexPhysicalId.id);
            }
        }

        // Deferred Persistent Deletion on Textures
        const pendingTexLen = assignerData.pendingTexDeletions.len;
        for (0..pendingTexLen) |i| {
            const index = pendingTexLen - 1 - i;
            const pending = &assignerData.pendingTexDeletions.buffer[index];

            if (pending.unusedCounter >= rc.FRAME_BUILDS_TILL_TRANSIENT_DELETION) {
                rendererQueue.append(.{ .removeTexture = pending.id }); // actual delete, now safe
                freeUpTexId(assignerData, pending.id); // ID only becomes reusable now
                assignerData.pendingTexDeletions.swapRemove(@intCast(index));
            } else pending.unusedCounter += 1;
        }

        // Deferred Persistent Deletion on Buffers
        const pendingBufLen = assignerData.pendingBufDeletions.len;
        for (0..pendingBufLen) |i| {
            const index = pendingBufLen - 1 - i;
            const pending = &assignerData.pendingBufDeletions.buffer[index];

            if (pending.unusedCounter >= rc.FRAME_BUILDS_TILL_TRANSIENT_DELETION) {
                rendererQueue.append(.{ .removeBuffer = pending.id }); // actual delete, now safe
                freeUpBufId(assignerData, pending.id); // ID only becomes reusable now
                assignerData.pendingBufDeletions.swapRemove(@intCast(index));
            } else pending.unusedCounter += 1;
        }

        // Debug
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("6.ResourceAssigner\n", .{});
            // Transient Buffer View:
            for (assignerData.usedTransientBufs.constSlice(), 0..) |transientBuf, i| {
                std.debug.print(" - Transient Buf {} -> (BufId {}) (unused for {} Builds)\n", .{ i, transientBuf.hardwareBuf.val(), transientBuf.unusedCounter });
            }
            std.debug.print("\n", .{});
            // Transient Texture View:
            for (assignerData.usedTransientTexes.constSlice(), 0..) |transientTex, i| {
                std.debug.print(" - Transient Tex {} -> (TexId {}) (unused for {} Builds)\n", .{ i, transientTex.hardwareTex.val(), transientTex.unusedCounter });
            }
            std.debug.print("\n", .{});
            // Buffers
            for (assignerData.bufAssigns.getConstItems(), 0..) |bufId, i| {
                const bufPassId = assignerData.bufAssigns.getKeyByIndex(@intCast(i));
                const bufName = try registryData.getBufferName(bufPassId);
                std.debug.print(" - Buf {s} assigned -> BufId {}\n", .{ bufName, bufId.val() });
            }
            std.debug.print("\n", .{});
            // Textures
            for (assignerData.texAssigns.getConstItems(), 0..) |texId, i| {
                const texPassId = assignerData.texAssigns.getKeyByIndex(@intCast(i));
                const texName = try registryData.getTextureName(texPassId);
                std.debug.print(" - Tex {s} assigned -> TexId {}\n", .{ texName, texId.val() });
            }
            std.debug.print("\n", .{});
        }
    }

    pub fn deferTextureDeletion(resourceAssigner: *AssignerData, rootTexId: TexPassId) !void {
        const texInf = resourceAssigner.rootTexPhysicalMap.getByKey(rootTexId);
        resourceAssigner.rootTexPhysicalMap.remove(rootTexId);
        resourceAssigner.pendingTexDeletions.append(.{ .id = texInf.id }) catch std.debug.print("ERROR: 6.ResourceAssigner: pendingTexDeletions append failed\n", .{});
    }

    pub fn deferBufferDeletion(resourceAssigner: *AssignerData, rootBufId: BufPassId) !void {
        const bufInf = resourceAssigner.rootBufPhysicalMap.getByKey(rootBufId);
        resourceAssigner.rootBufPhysicalMap.remove(rootBufId);
        resourceAssigner.pendingBufDeletions.append(.{ .id = bufInf.id }) catch std.debug.print("ERROR: 6.ResourceAssigner: pendingBufDeletions append failed\n", .{});
    }

    pub fn createTransientBuffer(bufDesc: BufDesc, bufId: BufId, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        const bufInf = BufInf{
            .id = bufId,
            .elementSize = bufDesc.elementSize,
            .len = bufDesc.len,
            .mem = bufDesc.mem,
            .resize = bufDesc.resize,
            .typ = bufDesc.typ,
            .update = bufDesc.update,
        };
        // RENDERER QUEUE SEND CREATE (AND UPDATE!) (Stop Renderer?)
        const arena = memoryMan.getGlobalArena();
        const AddBufPtr = @FieldType(RendererQueue.RendererEvent, "addBuffer");
        const AddBuf = std.meta.Child(AddBufPtr);
        const bufferPtr = try arena.create(AddBuf);
        bufferPtr.* = .{ .bufInf = bufInf, .data = null };
        rendererQueue.append(.{ .addBuffer = bufferPtr });

        std.debug.print("6.Resource Assigner: Transient Buf (BufId {}) Creation send to Renderer\n", .{bufInf.id});
    }

    pub fn deleteTransientBuffer(bufId: BufId, rendererQueue: *RendererQueue) void {
        // RENDERER QUEUE SEND DELETE (Stop Renderer missing?)
        rendererQueue.append(.{ .removeBuffer = bufId });
        std.debug.print("6.Resource Assigner: Transient Buf (BufId {}) Deletion send to Renderer\n", .{bufId});
    }

    pub fn createTransientTexture(texDesc: TexDesc, texId: TexId, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        const texInf = TexInf{
            .id = texId,
            .mem = texDesc.mem,
            .typ = texDesc.typ,
            .texUse = texDesc.texUse,
            .descriptors = texDesc.descriptors,
            .width = texDesc.width,
            .height = texDesc.height,
            .depth = texDesc.depth,
            .update = texDesc.update,
            .resize = texDesc.resize,
        };
        // RENDERER QUEUE SEND CREATE (AND UPDATE!) (Stop Renderer?)
        const arena = memoryMan.getGlobalArena();
        const AddTexPtr = @FieldType(RendererQueue.RendererEvent, "addTexture");
        const AddTex = std.meta.Child(AddTexPtr);
        const addTextureDataPtr = try arena.create(AddTex);
        addTextureDataPtr.* = .{ .texInf = texInf, .data = null };
        rendererQueue.append(.{ .addTexture = addTextureDataPtr });

        std.debug.print("6.Resource Assigner: Transient Tex (TexId {}) Creation send to Renderer\n", .{texInf.id});
    }

    pub fn deleteTransientTexture(texId: TexId, rendererQueue: *RendererQueue) void {
        // RENDERER QUEUE SEND DELETE (Stop Renderer missing?)
        rendererQueue.append(.{ .removeTexture = texId });
        std.debug.print("6.Resource Assigner: Transient Tex (TexId {}) Deletion send to Renderer\n", .{texId});
    }

    pub fn createBuffer(
        assignerData: *AssignerData,
        mapperData: *const MapperData,
        registryData: *const RegistryData,
        rootBuf: BufPassId,
        rendererQueue: *RendererQueue,
        memoryMan: *MemoryManager,
        authority: enum { frameGraph, manuel },
    ) !void {
        // Add Physical Assignment
        const bufId = try getFreeBufId(assignerData);

        const bufDesc = switch (authority) {
            .frameGraph => mapperData.bufGroupsPersistent.getByKey(rootBuf).bufDesc,
            .manuel => try registryData.getBufferDefinition(rootBuf),
        };

        const bufInf = BufInf{
            .id = bufId,
            .mem = bufDesc.mem,
            .elementSize = bufDesc.elementSize,
            .len = bufDesc.len,
            .typ = bufDesc.typ,
            .update = bufDesc.update,
            .resize = bufDesc.resize,
        };

        switch (authority) {
            .frameGraph => assignerData.rootBufPhysicalMap.upsert(rootBuf, bufInf),
            .manuel => {
                assignerData.manualBufs.upsert(rootBuf, bufInf);
                assignerData.bufAssigns.upsert(rootBuf, bufInf.id);
            },
        }

        // RENDERER QUEUE SEND CREATE (AND UPDATE!) (Stop Renderer?)
        const arena = memoryMan.getGlobalArena();
        const AddBufPtr = @FieldType(RendererQueue.RendererEvent, "addBuffer");
        const AddBuf = std.meta.Child(AddBufPtr);
        const bufferPtr = try arena.create(AddBuf);
        bufferPtr.* = .{ .bufInf = bufInf, .data = null };
        rendererQueue.append(.{ .addBuffer = bufferPtr });

        const rootBufName = try registryData.getBufferName(rootBuf);
        std.debug.print("6.Resource Assigner: Root Buf {s} (BufId {}) Creation send to Renderer\n", .{ rootBufName, bufId });
    }

    pub fn deleteBuffer(
        assignerData: *AssignerData,
        registryData: *const RegistryData,
        rootBufKey: BufPassId,
        rendererQueue: *RendererQueue,
        authority: enum { frameGraph, manuel },
    ) void {
        // Remove Physical Assignment

        const isUsed = switch (authority) {
            .frameGraph => assignerData.rootBufPhysicalMap.isKeyUsed(rootBufKey),
            .manuel => assignerData.manualBufs.isKeyUsed(rootBufKey),
        };

        if (isUsed == false) {
            const bufName = registryData.getBufferName(rootBufKey) catch undefined;
            std.debug.print("ERROR: 6.ResourceAssigner: Buffer {s} Authority {s} no Physical ID -> cant be destroyed!\n", .{ bufName, @tagName(authority) });
            return;
        }

        const bufInf = switch (authority) {
            .frameGraph => assignerData.rootBufPhysicalMap.getByKey(rootBufKey),
            .manuel => assignerData.manualBufs.getByKey(rootBufKey),
        };
        freeUpBufId(assignerData, bufInf.id);

        switch (authority) {
            .frameGraph => assignerData.rootBufPhysicalMap.remove(rootBufKey),
            .manuel => assignerData.manualBufs.remove(rootBufKey),
        }

        // RENDERER QUEUE SEND DELETE (Stop Renderer missing?)
        rendererQueue.append(.{ .removeBuffer = bufInf.id });

        const rootBufName = registryData.getBufferName(rootBufKey) catch "UNKNOWN";
        std.debug.print("6.Resource Assigner: Root Buf {s} (BufId {}) Deletion send to Renderer\n", .{ rootBufName, bufInf.id.val() });
    }

    pub fn createTexture(
        assignerData: *AssignerData,
        mapperData: *const MapperData,
        registryData: *const RegistryData,
        rootTexKey: TexPassId,
        rendererQueue: *RendererQueue,
        memoryMan: *MemoryManager,
        authority: enum { frameGraph, manuel },
    ) !void {
        // Add Physical Assignment
        const texId = try getFreeTexId(assignerData);

        const texDesc = switch (authority) {
            .frameGraph => mapperData.texGroupsPersistent.getByKey(rootTexKey).texDesc,
            .manuel => try registryData.getTextureDefinition(rootTexKey),
        };

        const texInf = TexInf{
            .id = texId,
            .mem = texDesc.mem,
            .typ = texDesc.typ,
            .texUse = texDesc.texUse,
            .descriptors = texDesc.descriptors,
            .width = texDesc.width,
            .height = texDesc.height,
            .depth = texDesc.depth,
            .update = texDesc.update,
            .resize = texDesc.resize,
        };

        switch (authority) {
            .frameGraph => assignerData.rootTexPhysicalMap.upsert(rootTexKey, texInf),
            .manuel => {
                assignerData.manualTexes.upsert(rootTexKey, texInf);
                assignerData.texAssigns.upsert(rootTexKey, texInf.id);
            },
        }

        // RENDERER QUEUE SEND CREATE (AND UPDATE!) (Stop Renderer?)
        const arena = memoryMan.getGlobalArena();
        const AddTexPtr = @FieldType(RendererQueue.RendererEvent, "addTexture");
        const AddTex = std.meta.Child(AddTexPtr);
        const addTextureDataPtr = try arena.create(AddTex);
        addTextureDataPtr.* = .{ .texInf = texInf, .data = null };
        rendererQueue.append(.{ .addTexture = addTextureDataPtr });

        const rootBufName = try registryData.getTextureName(rootTexKey);
        std.debug.print("6.Resource Assigner: Root Tex {s} (TexId {}) Creation send to Renderer\n", .{ rootBufName, texId });
    }

    pub fn deleteTexture(
        assignerData: *AssignerData,
        registryData: *const RegistryData,
        rootTexId: TexPassId,
        rendererQueue: *RendererQueue,
        authority: enum { frameGraph, manuel },
    ) void {
        // Remove Physical Assignment

        const isUsed = switch (authority) {
            .frameGraph => assignerData.rootTexPhysicalMap.isKeyUsed(rootTexId),
            .manuel => assignerData.manualTexes.isKeyUsed(rootTexId),
        };

        if (isUsed == false) {
            const texName = registryData.getTextureName(rootTexId) catch undefined;
            std.debug.print("ERROR: 6.ResourceAssigner: Texture {s} Authority {s} no Physical ID -> cant be destroyed!\n", .{ texName, @tagName(authority) });
            return;
        }

        const texInf = switch (authority) {
            .frameGraph => assignerData.rootTexPhysicalMap.getByKey(rootTexId),
            .manuel => assignerData.manualTexes.getByKey(rootTexId),
        };
        freeUpTexId(assignerData, texInf.id);

        switch (authority) {
            .frameGraph => assignerData.rootTexPhysicalMap.remove(rootTexId),
            .manuel => assignerData.manualTexes.remove(rootTexId),
        }

        // RENDERER QUEUE SEND DELETE (Stop Renderer missing?)
        rendererQueue.append(.{ .removeTexture = texInf.id });

        const rootBufName = registryData.getTextureName(rootTexId) catch "UNKNOWN";
        std.debug.print("6.Resource Assigner: Root Tex {s} (TexId {}) Deletion send to Renderer\n", .{ rootBufName, texInf.id.val() });
    }

    pub fn getFreeBufId(assignerData: *AssignerData) !BufId {
        const bufKey = assignerData.bufIdPool.tryReserveKey() orelse return error.BufIdsFullyUsed;
        return .id(bufKey);
    }

    pub fn freeUpBufId(assignerData: *AssignerData, bufId: BufId) void {
        assignerData.bufIdPool.freeKey(bufId.val());
    }

    pub fn getFreeTexId(assignerData: *AssignerData) !TexId {
        const texKey = assignerData.texIdPool.tryReserveKey() orelse return error.TexIdsFullyUsed;
        return .id(texKey);
    }

    pub fn freeUpTexId(assignerData: *AssignerData, texId: TexId) void {
        assignerData.texIdPool.freeKey(texId.val());
    }

    pub fn resolveBufferUpdateRequest(assignerData: *AssignerData, bufPassId: BufPassId) void {
        const updateRequest: ?pe.UpdateRequestEnum = switch (bufPassId) {
            rc.MainCamUB => .CamMainUpdate,
            rc.DebugCamUB => .CamDebugUpdate,
            rc.ImguiIB => .GuiUpdate,
            rc.ImguiVB => .GuiUpdate,
            rc.EntitySB => .EntityUpdate,
            else => null,
        };
        if (updateRequest) |request| assignerData.updateRequests.upsert(@intFromEnum(request), request);
    }

    pub fn resolveTextureUpdateRequest(assignerData: *AssignerData, texPassId: TexPassId) void {
        const updateRequest: ?pe.UpdateRequestEnum = switch (texPassId) {
            rc.TestTileTex => .TestTileUpdate,
            rc.ImguiFontTex => .GuiUpdate,
            else => null,
        };
        if (updateRequest) |request| {
            assignerData.updateRequests.upsert(@intFromEnum(request), request);
        }
    }
};

fn bufDescEqual(bufDesc1: *const BufDesc, bufDesc2: *const BufDesc) bool {
    return std.meta.eql(bufDesc1.*, bufDesc2.*);
}

fn texDescEqual(texDesc1: *const TexDesc, texDesc2: *const TexDesc) bool {
    return std.meta.eql(texDesc1.*, texDesc2.*);
}
