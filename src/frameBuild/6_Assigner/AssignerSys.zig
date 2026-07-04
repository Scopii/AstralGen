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

const getResKey = @import("../../frameBuild/components.zig").getResKey;
const getResTyp = @import("../../frameBuild/components.zig").getResTyp;

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
    pub fn build(
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

        // Recycling! Move slots into unused pools
        for (assignerData.usedTransientSlots.constSlice()) |slot| {
            switch (slot) {
                .buf => |b| assignerData.unusedTransientBufs.append(b) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to unusedTransientBufs\n", .{}),
                .tex => |t| assignerData.unusedTransientTexes.append(t) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to unusedTransientTexes\n", .{}),
            }
        }
        assignerData.usedTransientSlots.clear();

        // Pooling
        for (groupData.sharedResLifetimes.constSlice()) |sharedLifetime| {
            const desc = mapperData.transientGroups.getByKey(sharedLifetime.resKey).desc;

            switch (getResTyp(sharedLifetime.resKey)) {
                .Buf => {
                    var candidateIndex: ?u16 = null;

                    for (assignerData.unusedTransientBufs.constSlice(), 0..) |transientBuf, i| {
                        if (bufDescEqual(&transientBuf.bufDesc, &desc.bufDesc)) {
                            candidateIndex = @intCast(i);
                            break;
                        }
                    }
                    if (candidateIndex) |ci| {
                        var candidate = assignerData.unusedTransientBufs.swapRemoveReturn(ci);
                        candidate.unusedCounter = 0;
                        assignerData.usedTransientSlots.append(.{ .buf = candidate }) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientSlots\n", .{});
                    } else {
                        const candidate = TransientBuffer{ .bufDesc = desc.bufDesc, .hardwareBuf = try getFreeBufId(assignerData) };
                        try createTransientBuffer(desc.bufDesc, candidate.hardwareBuf, rendererQueue, memoryMan);
                        assignerData.usedTransientSlots.append(.{ .buf = candidate }) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientSlots\n", .{});
                    }
                },
                .Tex => {
                    var candidateIndex: ?u16 = null;

                    for (assignerData.unusedTransientTexes.constSlice(), 0..) |transientTex, i| {
                        if (texDescEqual(&transientTex.texDesc, &desc.texDesc)) {
                            candidateIndex = @intCast(i);
                            break;
                        }
                    }
                    if (candidateIndex) |ci| {
                        var candidate = assignerData.unusedTransientTexes.swapRemoveReturn(ci);
                        candidate.unusedCounter = 0;
                        assignerData.usedTransientSlots.append(.{ .tex = candidate }) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientSlots\n", .{});
                    } else {
                        const candidate = TransientTexture{ .texDesc = desc.texDesc, .hardwareTex = try getFreeTexId(assignerData) };
                        try createTransientTexture(desc.texDesc, candidate.hardwareTex, rendererQueue, memoryMan);
                        assignerData.usedTransientSlots.append(.{ .tex = candidate }) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientSlots\n", .{});
                    }
                },
            }
        }

        // Assignments
        for (groupData.shareIndexMap.getConstItems(), 0..) |sharedIndex, i| {
            const rootKey = groupData.shareIndexMap.getKeyByIndex(@intCast(i));
            const group = mapperData.transientGroups.getByKey(rootKey);

            switch (assignerData.usedTransientSlots.buffer[sharedIndex]) {
                .buf => |slot| {
                    for (group.firstMapIndex..group.lastMapIndex + 1) |mapIndex| {
                        const memberKey = mapperData.transientMap.getKeyByIndex(@intCast(mapIndex));
                        const bufPassId: BufPassId = .id(memberKey);

                        if (assignerData.bufAssigns.isKeyUsed(bufPassId)) {
                            const bufName = try registryData.getBufferName(bufPassId);
                            std.debug.print("ERROR: 6.ResourceAssigner: Buffer Name {s} already assigned!\n", .{bufName});
                            return error.BufEnumAlreadyAssigned;
                        }
                        assignerData.bufAssigns.upsert(bufPassId, slot.hardwareBuf);
                    }
                },
                .tex => |slot| {
                    for (group.firstMapIndex..group.lastMapIndex + 1) |mapIndex| {
                        const memberKey = mapperData.transientMap.getKeyByIndex(@intCast(mapIndex));
                        const texPassId: TexPassId = .id(memberKey - rc.BUF_MAX);

                        if (assignerData.texAssigns.isKeyUsed(texPassId)) {
                            const texName = try registryData.getTextureName(texPassId);
                            std.debug.print("ERROR: 6.ResourceAssigner: Texture Name {s} already assigned!\n", .{texName});
                            return error.TexEnumAlreadyAssigned;
                        }
                        assignerData.texAssigns.upsert(texPassId, slot.hardwareTex);
                    }
                },
            }
        }

        // Cleanup Buffers
        const unusedBufsLen = assignerData.unusedTransientBufs.len;
        for (0..unusedBufsLen) |i| {
            const index = unusedBufsLen - 1 - i;
            const transientBuf = &assignerData.unusedTransientBufs.buffer[index];

            if (transientBuf.unusedCounter >= rc.FRAME_BUILDS_TILL_TRANSIENT_DELETION) {
                deleteTransientBuffer(transientBuf.hardwareBuf, rendererQueue);
                freeUpBufId(assignerData, transientBuf.hardwareBuf);
                assignerData.unusedTransientBufs.swapRemove(@intCast(index));
            } else {
                transientBuf.unusedCounter += 1;
            }
        }

        // Cleanup Textures
        const unusedTexesLen = assignerData.unusedTransientTexes.len;
        for (0..unusedTexesLen) |i| {
            const index = unusedTexesLen - 1 - i;
            const transientTex = &assignerData.unusedTransientTexes.buffer[index];

            if (transientTex.unusedCounter >= rc.FRAME_BUILDS_TILL_TRANSIENT_DELETION) {
                deleteTransientTexture(transientTex.hardwareTex, rendererQueue);
                freeUpTexId(assignerData, transientTex.hardwareTex);
                assignerData.unusedTransientTexes.swapRemove(@intCast(index));
            } else {
                transientTex.unusedCounter += 1;
            }
        }

        // PERSISTENT RESOURCES //

        // Creating, Deleting and Recreating Persistent Resources
        for (comparatorData.persistentChanges.constSlice()) |groupChange| {
            const rootKey = groupChange.rootResource;
            const keyTyp = getResTyp(rootKey);

            switch (groupChange.change) {
                .unchanged => {},
                .deleted => switch (keyTyp) {
                    .Buf => try deferBufferDeletion(assignerData, .id(rootKey)), // or deleteBuffer
                    .Tex => try deferTextureDeletion(assignerData, .id(rootKey - rc.BUF_MAX)), // or deleteTexture
                },
                .created => switch (keyTyp) {
                    .Buf => {
                        try createBuffer(assignerData, mapperData, registryData, .id(rootKey), rendererQueue, memoryMan, .frameGraph);
                        resolveBufferUpdateRequest(assignerData, .id(rootKey));
                    },
                    .Tex => {
                        try createTexture(assignerData, mapperData, registryData, .id(rootKey - rc.BUF_MAX), rendererQueue, memoryMan, .frameGraph);
                        resolveTextureUpdateRequest(assignerData, .id(rootKey - rc.BUF_MAX));
                    },
                },
                .newDesc, .newPass, .newPassAndDesc => switch (keyTyp) {
                    .Buf => {
                        try deferBufferDeletion(assignerData, .id(rootKey)); // or deleteBuffer
                        try createBuffer(assignerData, mapperData, registryData, .id(rootKey), rendererQueue, memoryMan, .frameGraph);
                        resolveBufferUpdateRequest(assignerData, .id(rootKey));
                    },
                    .Tex => {
                        try deferTextureDeletion(assignerData, .id(rootKey - rc.BUF_MAX)); // or deleteTexture
                        try createTexture(assignerData, mapperData, registryData, .id(rootKey - rc.BUF_MAX), rendererQueue, memoryMan, .frameGraph);
                        resolveTextureUpdateRequest(assignerData, .id(rootKey - rc.BUF_MAX));
                    },
                },
            }
        }

        if (rc.FRAME_GRAPH_DEBUG) std.debug.print("\n", .{});

        for (mapperData.persistentGroups.getConstItems(), 0..) |group, i| {
            const rootKey = mapperData.persistentGroups.getKeyByIndex(@intCast(i));

            switch (getResTyp(rootKey)) {
                .Buf => {
                    const physicalInf = assignerData.rootBufPhysicalMap.getByKey(.id(rootKey));
                    for (group.firstMapIndex..group.lastMapIndex + 1) |mapIndex| {
                        const memberKey = mapperData.persistentMap.getKeyByIndex(@intCast(mapIndex));
                        const bufPassId: BufPassId = .id(memberKey);

                        if (assignerData.bufAssigns.isKeyUsed(bufPassId)) {
                            const bufName = try registryData.getBufferName(bufPassId);
                            std.debug.print("ERROR: 6.ResourceAssigner: Buffer {s} already assigned!\n", .{bufName});
                            return error.BufEnumAlreadyAssigned;
                        }
                        assignerData.bufAssigns.upsert(bufPassId, physicalInf.id);
                    }
                },
                .Tex => {
                    const physicalInf = assignerData.rootTexPhysicalMap.getByKey(.id(rootKey - rc.BUF_MAX)); 
                    for (group.firstMapIndex..group.lastMapIndex + 1) |mapIndex| {
                        const memberKey = mapperData.persistentMap.getKeyByIndex(@intCast(mapIndex));
                        const texPassId: TexPassId = .id(memberKey - rc.BUF_MAX);

                        if (assignerData.texAssigns.isKeyUsed(texPassId)) {
                            const texName = try registryData.getTextureName(texPassId);
                            std.debug.print("ERROR: 6.ResourceAssigner: Texture {s} already assigned!\n", .{texName});
                            return error.BufEnumAlreadyAssigned;
                        }
                        assignerData.texAssigns.upsert(texPassId, physicalInf.id);
                    }
                },
            }
        }

        // Create Manuel Texture Assignments
        for (assignerData.manualTexes.getConstItems(), 0..) |texInf, i| {
            const texPassId = assignerData.manualTexes.getKeyByIndex(@intCast(i));
            assignerData.texAssigns.upsert(texPassId, texInf.id);
        }

        // Create Manuel Buffer Assignments
        for (assignerData.manualBufs.getConstItems(), 0..) |bufInf, i| {
            const enumKey = assignerData.manualBufs.getKeyByIndex(@intCast(i));
            assignerData.bufAssigns.upsert(enumKey, bufInf.id);
        }

        // Deferred Persistent Textures Deletion
        const pendingTexLen = assignerData.pendingTexDeletions.len;
        for (0..pendingTexLen) |i| {
            const index = pendingTexLen - 1 - i;
            const pending = &assignerData.pendingTexDeletions.buffer[index];

            if (pending.unusedCounter >= rc.FRAME_BUILDS_TILL_TRANSIENT_DELETION) {
                rendererQueue.append(.{ .removeTexture = pending.id }); 
                freeUpTexId(assignerData, pending.id); 
                assignerData.pendingTexDeletions.swapRemove(@intCast(index));
            } else pending.unusedCounter += 1;
        }

        // Deferred Persistent Buffers Deletion
        const pendingBufLen = assignerData.pendingBufDeletions.len;
        for (0..pendingBufLen) |i| {
            const index = pendingBufLen - 1 - i;
            const pending = &assignerData.pendingBufDeletions.buffer[index];

            if (pending.unusedCounter >= rc.FRAME_BUILDS_TILL_TRANSIENT_DELETION) {
                rendererQueue.append(.{ .removeBuffer = pending.id }); 
                freeUpBufId(assignerData, pending.id); 
                assignerData.pendingBufDeletions.swapRemove(@intCast(index));
            } else pending.unusedCounter += 1;
        }

        // Debug
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("6.ResourceAssigner\n", .{});
            for (assignerData.usedTransientSlots.constSlice(), 0..) |slot, i| {
                switch (slot) {
                    .buf => |buf| std.debug.print(" - Transient Slot {} -> Buf (BufId {}) (unused for {} Builds)\n", .{ i, buf.hardwareBuf.val(), buf.unusedCounter }),
                    .tex => |tex| std.debug.print(" - Transient Slot {} -> Tex (TexId {}) (unused for {} Builds)\n", .{ i, tex.hardwareTex.val(), tex.unusedCounter }),
                }
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
            .frameGraph => mapperData.persistentGroups.getByKey(getResKey(rootBuf)).desc.bufDesc,
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
        rootTex: TexPassId,
        rendererQueue: *RendererQueue,
        memoryMan: *MemoryManager,
        authority: enum { frameGraph, manuel },
    ) !void {
        // Add Physical Assignment
        const texId = try getFreeTexId(assignerData);

        const texDesc = switch (authority) {
            .frameGraph => mapperData.persistentGroups.getByKey(getResKey(rootTex)).desc.texDesc,
            .manuel => try registryData.getTextureDefinition(rootTex),
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
            .frameGraph => assignerData.rootTexPhysicalMap.upsert(rootTex, texInf),
            .manuel => {
                assignerData.manualTexes.upsert(rootTex, texInf);
                assignerData.texAssigns.upsert(rootTex, texInf.id);
            },
        }

        // RENDERER QUEUE SEND CREATE (AND UPDATE!) (Stop Renderer?)
        const arena = memoryMan.getGlobalArena();
        const AddTexPtr = @FieldType(RendererQueue.RendererEvent, "addTexture");
        const AddTex = std.meta.Child(AddTexPtr);
        const addTextureDataPtr = try arena.create(AddTex);
        addTextureDataPtr.* = .{ .texInf = texInf, .data = null };
        rendererQueue.append(.{ .addTexture = addTextureDataPtr });

        const rootBufName = try registryData.getTextureName(rootTex);
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
