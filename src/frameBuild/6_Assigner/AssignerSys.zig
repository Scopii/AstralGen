const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const TransientTexture = @import("../../frameBuild/components.zig").TransientTexture;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const TransientBuffer = @import("../../frameBuild/components.zig").TransientBuffer;
const TextureMeta = @import("../../render/types/res/TextureMeta.zig").TextureMeta;
const BufferMeta = @import("../../render/types/res/BufferMeta.zig").BufferMeta;
const RendererQueue = @import("../../render/RendererQueue.zig").RendererQueue;
const MemoryManager = @import("../../core/MemoryManager.zig").MemoryManager;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const TexId = @import("../../.configs/idConfig.zig").TexId;
const BufId = @import("../../.configs/idConfig.zig").BufId;
const rc = @import("../../.configs/renderConfig.zig");
const pe = @import("../enums.zig");
const std = @import("std");
const TexInf = TextureMeta.TexInf;
const BufInf = BufferMeta.BufInf;

const getResTyp = @import("../../frameBuild/components.zig").getResTyp;
const texToRes = @import("../../frameBuild/components.zig").texToRes;
const bufToRes = @import("../../frameBuild/components.zig").bufToRes;
const resToBuf = @import("../../frameBuild/components.zig").resToBuf;
const resToTex = @import("../../frameBuild/components.zig").resToTex;

const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const MapperData = @import("../5.1_Mapper/MapperData.zig").MapperData;
const ComparatorData = @import("../5.3_Comparator/ComparatorData.zig").ComparatorData;
const GroupData = @import("../5.4_Group/GroupData.zig").GroupData;
const AssignerData = @import("AssignerData.zig").AssignerData;

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

        assignerData.unusedTransientBufs.appendSliceAssumeCapacity(assignerData.usedTransientBufs.constSlice());
        assignerData.unusedTransientTexes.appendSliceAssumeCapacity(assignerData.usedTransientTexes.constSlice());

        assignerData.usedTransientBufs.clear();
        assignerData.usedTransientTexes.clear();

        // Buffer Pooling
        for (groupData.sharedBufLifetimes.constSlice()) |sharedBufLifetime| {
            const desc = mapperData.transientGroups.getByKey(sharedBufLifetime.resKey).desc;
            var candidateIndex: ?u16 = null;

            for (assignerData.unusedTransientBufs.constSlice(), 0..) |transientBuf, i| {
                if (bufDescEqual(&transientBuf.bufDesc, &desc.bufDesc)) {
                    candidateIndex = @intCast(i);
                    break;
                }
            }
            if (candidateIndex) |index| {
                var candidate = assignerData.unusedTransientBufs.swapRemoveReturn(index);
                candidate.unusedCounter = 0;
                assignerData.usedTransientBufs.append(candidate) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientBufs\n", .{});
            } else {
                const candidate = TransientBuffer{ .bufDesc = desc.bufDesc, .hardwareBuf = try getFreeBufId(assignerData) };
                try createTransientBuffer(desc.bufDesc, candidate.hardwareBuf, rendererQueue, memoryMan);
                assignerData.usedTransientBufs.append(candidate) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientBufs\n", .{});
            }
        }

        // Texture Pooling
        for (groupData.sharedTexLifetimes.constSlice()) |sharedTexLifetime| {
            const desc = mapperData.transientGroups.getByKey(sharedTexLifetime.resKey).desc;
            var candidateIndex: ?u16 = null;

            for (assignerData.unusedTransientTexes.constSlice(), 0..) |transientTex, i| {
                if (texDescEqual(&transientTex.texDesc, &desc.texDesc)) {
                    candidateIndex = @intCast(i);
                    break;
                }
            }
            if (candidateIndex) |index| {
                var candidate = assignerData.unusedTransientTexes.swapRemoveReturn(index);
                candidate.unusedCounter = 0;
                assignerData.usedTransientTexes.append(candidate) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientTexes\n", .{});
            } else {
                const candidate = TransientTexture{ .texDesc = desc.texDesc, .hardwareTex = try getFreeTexId(assignerData) };
                try createTransientTexture(desc.texDesc, candidate.hardwareTex, rendererQueue, memoryMan);
                assignerData.usedTransientTexes.append(candidate) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientTexes\n", .{});
            }
        }

        // Assignments
        for (groupData.bufShareIndexMap.getConstItems(), 0..) |sharedIndex, i| {
            const rootRes = groupData.bufShareIndexMap.getKeyByIndex(@intCast(i));
            const group = mapperData.transientGroups.getByKey(bufToRes(rootRes));

            const bufHardwareId = assignerData.usedTransientBufs.buffer[sharedIndex].hardwareBuf;

            for (group.firstMapIndex..group.lastMapIndex + 1) |mapIndex| {
                const memeberRes = mapperData.transientMap.getKeyByIndex(@intCast(mapIndex));
                const bufPassId: BufPassId = resToBuf(memeberRes);

                if (assignerData.bufAssigns.isKeyUsed(bufPassId)) {
                    const bufName = try registryData.getBufferName(bufPassId);
                    std.debug.print("ERROR: 6.ResourceAssigner: Buffer Name {s} already assigned!\n", .{bufName});
                    return error.BufEnumAlreadyAssigned;
                }
                assignerData.bufAssigns.upsert(bufPassId, bufHardwareId);
            }
        }

        for (groupData.texShareIndexMap.getConstItems(), 0..) |sharedIndex, i| {
            const rootRes = groupData.texShareIndexMap.getKeyByIndex(@intCast(i));
            const group = mapperData.transientGroups.getByKey(texToRes(rootRes));

            const texHardwareId = assignerData.usedTransientTexes.buffer[sharedIndex].hardwareTex;

            for (group.firstMapIndex..group.lastMapIndex + 1) |mapIndex| {
                const memberRes = mapperData.transientMap.getKeyByIndex(@intCast(mapIndex));
                const texPassId: TexPassId = resToTex(memberRes);

                if (assignerData.texAssigns.isKeyUsed(texPassId)) {
                    const texName = try registryData.getTextureName(texPassId);
                    std.debug.print("ERROR: 6.ResourceAssigner: Texture Name {s} already assigned!\n", .{texName});
                    return error.TexEnumAlreadyAssigned;
                }
                assignerData.texAssigns.upsert(texPassId, texHardwareId);
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
                .unchanged, .newPass => {},
                .deleted => switch (keyTyp) {
                    .Buf => {
                        if (assignerData.manualBufs.isKeyUsed(resToBuf(rootKey))) continue;

                        try deferBufferDeletion(assignerData, resToBuf(rootKey)); // or deleteBuffer
                    },
                    .Tex => {
                        if (assignerData.manualTexes.isKeyUsed(resToTex(rootKey))) continue;

                        try deferTextureDeletion(assignerData, resToTex(rootKey)); // or deleteTexture
                    },
                },
                .created => switch (keyTyp) {
                    .Buf => {
                        if (assignerData.manualBufs.isKeyUsed(resToBuf(rootKey))) continue;

                        try createBuffer(assignerData, mapperData, registryData, resToBuf(rootKey), rendererQueue, memoryMan);
                        resolveBufferUpdateRequest(assignerData, resToBuf(rootKey));
                    },
                    .Tex => {
                        if (assignerData.manualTexes.isKeyUsed(resToTex(rootKey))) continue;

                        try createTexture(assignerData, mapperData, registryData, resToTex(rootKey), rendererQueue, memoryMan);
                        resolveTextureUpdateRequest(assignerData, resToTex(rootKey));
                    },
                },
                .newDesc, .newPassAndDesc => switch (keyTyp) {
                    .Buf => {
                        if (assignerData.manualBufs.isKeyUsed(resToBuf(rootKey))) {
                            const bufName = try registryData.getBufferName(resToBuf(rootKey));
                            std.debug.print("WARN: desc changed on manual Buffer! {s} -> graph wont recreate\n", .{bufName});
                            continue;
                        }

                        try deferBufferDeletion(assignerData, resToBuf(rootKey)); // or deleteBuffer
                        try createBuffer(assignerData, mapperData, registryData, resToBuf(rootKey), rendererQueue, memoryMan);
                        resolveBufferUpdateRequest(assignerData, resToBuf(rootKey));
                    },
                    .Tex => {
                        if (assignerData.manualTexes.isKeyUsed(resToTex(rootKey))) {
                            const texName = try registryData.getTextureName(resToTex(rootKey));
                            std.debug.print("WARN: desc changed on manual Texture! {s} -> graph wont recreate\n", .{texName});
                            continue;
                        }

                        try deferTextureDeletion(assignerData, resToTex(rootKey)); // or deleteTexture
                        try createTexture(assignerData, mapperData, registryData, resToTex(rootKey), rendererQueue, memoryMan);
                        resolveTextureUpdateRequest(assignerData, resToTex(rootKey));
                    },
                },
            }
        }

        if (rc.FRAME_GRAPH_DEBUG) std.debug.print("\n", .{});

        for (mapperData.persistentGroups.getConstItems(), 0..) |group, i| {
            const rootKey = mapperData.persistentGroups.getKeyByIndex(@intCast(i));

            switch (getResTyp(rootKey)) {
                .Buf => {
                    const isManual = assignerData.manualBufs.isKeyUsed(resToBuf(rootKey));
                    const bufId = if (isManual) assignerData.manualBufs.getByKey(resToBuf(rootKey)).id else assignerData.rootBufPhysicalMap.getByKey(resToBuf(rootKey));

                    for (group.firstMapIndex..group.lastMapIndex + 1) |mapIndex| {
                        const memberKey = mapperData.persistentMap.getKeyByIndex(@intCast(mapIndex));
                        const bufPassId = resToBuf(memberKey);

                        if (assignerData.bufAssigns.isKeyUsed(bufPassId)) {
                            const bufName = try registryData.getBufferName(bufPassId);
                            std.debug.print("ERROR: 6.ResourceAssigner: Buffer {s} already assigned!\n", .{bufName});
                            return error.BufEnumAlreadyAssigned;
                        }
                        assignerData.bufAssigns.upsert(bufPassId, bufId);
                    }
                },
                .Tex => {
                    const isManual = assignerData.manualTexes.isKeyUsed(resToTex(rootKey));
                    const texId = if (isManual) assignerData.manualTexes.getByKey(resToTex(rootKey)).id else assignerData.rootTexPhysicalMap.getByKey(resToTex(rootKey));

                    for (group.firstMapIndex..group.lastMapIndex + 1) |mapIndex| {
                        const memberKey = mapperData.persistentMap.getKeyByIndex(@intCast(mapIndex));
                        const texPassId = resToTex(memberKey);

                        if (assignerData.texAssigns.isKeyUsed(texPassId)) {
                            const texName = try registryData.getTextureName(texPassId);
                            std.debug.print("ERROR: 6.ResourceAssigner: Texture {s} already assigned!\n", .{texName});
                            return error.TexEnumAlreadyAssigned;
                        }
                        assignerData.texAssigns.upsert(texPassId, texId);
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
            for (assignerData.usedTransientBufs.constSlice(), 0..) |buf, i| {
                std.debug.print(" - Transient Buf {} -> Buf (BufId {}) (unused for {} Builds)\n", .{ i, buf.hardwareBuf.val(), buf.unusedCounter });
            }
            for (assignerData.usedTransientTexes.constSlice(), 0..) |tex, i| {
                std.debug.print(" - Transient Tex {} -> Tex (TexId {}) (unused for {} Builds)\n", .{ i, tex.hardwareTex.val(), tex.unusedCounter });
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
        if (resourceAssigner.rootTexPhysicalMap.isKeyUsed(rootTexId) == false) return error.rootTexKeyNotUsed;
        const texId = resourceAssigner.rootTexPhysicalMap.getByKey(rootTexId);
        resourceAssigner.rootTexPhysicalMap.remove(rootTexId);
        resourceAssigner.pendingTexDeletions.append(.{ .id = texId }) catch std.debug.print("ERROR: 6.ResourceAssigner: pendingTexDeletions append failed\n", .{});
    }

    pub fn deferBufferDeletion(resourceAssigner: *AssignerData, rootBufId: BufPassId) !void {
        if (resourceAssigner.rootBufPhysicalMap.isKeyUsed(rootBufId) == false) return error.rootBufKeyNotUsed;
        const bufId = resourceAssigner.rootBufPhysicalMap.getByKey(rootBufId);
        resourceAssigner.rootBufPhysicalMap.remove(rootBufId);
        resourceAssigner.pendingBufDeletions.append(.{ .id = bufId }) catch std.debug.print("ERROR: 6.ResourceAssigner: pendingBufDeletions append failed\n", .{});
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
        rendererQueue.append(.{ .removeBuffer = bufId }); // (Stop Renderer missing?)
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
        rendererQueue.append(.{ .removeTexture = texId }); // (Stop Renderer missing?)
        std.debug.print("6.Resource Assigner: Transient Tex (TexId {}) Deletion send to Renderer\n", .{texId});
    }

    pub fn createBufferManuel(assignerData: *AssignerData, registryData: *const RegistryData, rootBuf: BufPassId, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        if (assignerData.rootBufPhysicalMap.isKeyUsed(rootBuf)) return error.GraphAlreadyOwnsBuffer;

        const bufId = try getFreeBufId(assignerData);
        const bufDesc = try registryData.getBufferDefinition(rootBuf);
        if (bufDesc.share == .transient) return error.ManualBufferCantBeTransient;
        // if (bufDesc.fitPass == true) return error.ManualBufferCantResize;

        const bufInf = BufInf{
            .id = bufId,
            .mem = bufDesc.mem,
            .elementSize = bufDesc.elementSize,
            .len = bufDesc.len,
            .typ = bufDesc.typ,
            .update = bufDesc.update,
            .resize = bufDesc.resize,
        };
        assignerData.manualBufs.upsert(rootBuf, bufInf);
        assignerData.bufAssigns.upsert(rootBuf, bufInf.id);

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

    pub fn createBuffer(
        assignerData: *AssignerData,
        mapperData: *const MapperData,
        registryData: *const RegistryData,
        rootBuf: BufPassId,
        rendererQueue: *RendererQueue,
        memoryMan: *MemoryManager,
    ) !void {
        const bufId = try getFreeBufId(assignerData);
        const bufDesc = mapperData.persistentGroups.getByKey(bufToRes(rootBuf)).desc.bufDesc;

        const bufInf = BufInf{
            .id = bufId,
            .mem = bufDesc.mem,
            .elementSize = bufDesc.elementSize,
            .len = bufDesc.len,
            .typ = bufDesc.typ,
            .update = bufDesc.update,
            .resize = bufDesc.resize,
        };
        assignerData.rootBufPhysicalMap.upsert(rootBuf, bufId);

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

    pub fn deleteBufferManuel(assignerData: *AssignerData, registryData: *const RegistryData, rootBufKey: BufPassId, rendererQueue: *RendererQueue) void {
        const isUsed = assignerData.manualBufs.isKeyUsed(rootBufKey);
        if (isUsed == false) {
            const bufName = registryData.getBufferName(rootBufKey) catch undefined;
            std.debug.print("ERROR: 6.ResourceAssigner: Buffer {s} no Physical ID -> cant be destroyed!\n", .{bufName});
            return;
        }
        const bufId = assignerData.manualBufs.getByKey(rootBufKey).id;
        freeUpBufId(assignerData, bufId);
        assignerData.manualBufs.remove(rootBufKey);
        rendererQueue.append(.{ .removeBuffer = bufId }); // (Stop Renderer missing?)

        const rootBufName = registryData.getBufferName(rootBufKey) catch "UNKNOWN";
        std.debug.print("6.Resource Assigner: Root Buf {s} (BufId {}) Deletion send to Renderer\n", .{ rootBufName, bufId.val() });
    }

    pub fn deleteBuffer(assignerData: *AssignerData, registryData: *const RegistryData, rootBufKey: BufPassId, rendererQueue: *RendererQueue) void {
        const isUsed = assignerData.rootBufPhysicalMap.isKeyUsed(rootBufKey);
        if (isUsed == false) {
            const bufName = registryData.getBufferName(rootBufKey) catch undefined;
            std.debug.print("ERROR: 6.ResourceAssigner: Buffer {s} no Physical ID -> cant be destroyed!\n", .{bufName});
            return;
        }
        const bufId = assignerData.rootBufPhysicalMap.getByKey(rootBufKey).id;
        freeUpBufId(assignerData, bufId);
        assignerData.rootBufPhysicalMap.remove(rootBufKey);
        rendererQueue.append(.{ .removeBuffer = bufId }); // (Stop Renderer missing?)

        const rootBufName = registryData.getBufferName(rootBufKey) catch "UNKNOWN";
        std.debug.print("6.Resource Assigner: Root Buf {s} (BufId {}) Deletion send to Renderer\n", .{ rootBufName, bufId.val() });
    }

    pub fn createTextureManuel(assignerData: *AssignerData, registryData: *const RegistryData, rootTex: TexPassId, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        if (assignerData.rootTexPhysicalMap.isKeyUsed(rootTex)) return error.GraphAlreadyOwnsTexture;

        const texId = try getFreeTexId(assignerData);
        const texDesc = try registryData.getTextureDefinition(rootTex);
        if (texDesc.share == .transient) return error.ManualTextureCantBeTransient;
        if (texDesc.fitPass) return error.ManualTextureCantFitPass;

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
        assignerData.manualTexes.upsert(rootTex, texInf);
        assignerData.texAssigns.upsert(rootTex, texId);

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

    pub fn createTexture(
        assignerData: *AssignerData,
        mapperData: *const MapperData,
        registryData: *const RegistryData,
        rootTex: TexPassId,
        rendererQueue: *RendererQueue,
        memoryMan: *MemoryManager,
    ) !void {
        const texId = try getFreeTexId(assignerData);
        const desc = mapperData.persistentGroups.getByKey(texToRes(rootTex)).desc.texDesc;

        const texInf = TexInf{
            .id = texId,
            .mem = desc.mem,
            .typ = desc.typ,
            .texUse = desc.texUse,
            .descriptors = desc.descriptors,
            .width = desc.width,
            .height = desc.height,
            .depth = desc.depth,
            .update = desc.update,
            .resize = desc.resize,
        };
        assignerData.rootTexPhysicalMap.upsert(rootTex, texId);

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

    pub fn deleteTextureManuel(assignerData: *AssignerData, registryData: *const RegistryData, rootTexId: TexPassId, rendererQueue: *RendererQueue) void {
        const isUsed = assignerData.manualTexes.isKeyUsed(rootTexId);
        if (isUsed == false) {
            const texName = registryData.getTextureName(rootTexId) catch undefined;
            std.debug.print("ERROR: 6.ResourceAssigner: Texture {s} no Physical ID -> cant be destroyed!\n", .{texName});
            return;
        }
        const texInf = assignerData.manualTexes.getByKey(rootTexId);
        freeUpTexId(assignerData, texInf.id);

        assignerData.manualTexes.remove(rootTexId);
        rendererQueue.append(.{ .removeTexture = texInf.id }); // (Stop Renderer missing?)

        const rootBufName = registryData.getTextureName(rootTexId) catch "UNKNOWN";
        std.debug.print("6.Resource Assigner: Root Tex {s} (TexId {}) Deletion send to Renderer\n", .{ rootBufName, texInf.id.val() });
    }

    pub fn deleteTexture(assignerData: *AssignerData, registryData: *const RegistryData, rootTexId: TexPassId, rendererQueue: *RendererQueue) void {
        const isUsed = assignerData.rootTexPhysicalMap.isKeyUsed(rootTexId);
        if (isUsed == false) {
            const texName = registryData.getTextureName(rootTexId) catch undefined;
            std.debug.print("ERROR: 6.ResourceAssigner: Texture {s} no Physical ID -> cant be destroyed!\n", .{texName});
            return;
        }
        const texInf = assignerData.rootTexPhysicalMap.getByKey(rootTexId);
        freeUpTexId(assignerData, texInf.id);

        assignerData.rootTexPhysicalMap.remove(rootTexId);
        rendererQueue.append(.{ .removeTexture = texInf.id }); // (Stop Renderer missing?)

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
