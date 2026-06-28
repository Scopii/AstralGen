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

const GroupMergerData = @import("../5.4_groupMerger/GroupMergerData.zig").GroupMergerData;
const ResourceAssignerData = @import("ResourceAssignerData.zig").ResourceAssignerData;
const ResourceMapperData = @import("../5.1_resourceMapper/ResourceMapperData.zig").ResourceMapperData;
const MappingComparatorData = @import("../5.3_mappingComparator/MappingComparatorData.zig").MappingComparatorData;
const ResourceExtractorData = @import("../2_resourceExtractor/ResourceExtractorData.zig").ResourceExtractorData;
const ResourceRegistryData = @import("../0_resourceRegistry/ResourceRegistryData.zig").ResourceRegistryData;

const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const TexInf = TextureMeta.TexInf;
const BufInf = BufferMeta.BufInf;

// Step 6

pub const ResourceAssignerSys = struct {
    pub fn buildPersistentResources(
        resourceAssigner: *ResourceAssignerData,
        resourceExtractor: *const ResourceExtractorData,
        resourceMapper: *const ResourceMapperData,
        mappingComparator: *const MappingComparatorData,
        groupMerger: *const GroupMergerData,
        resourceRegistry: *const ResourceRegistryData,
        rendererQueue: *RendererQueue,
        memoryMan: *MemoryManager,
    ) !void {
        // Resets
        resourceAssigner.updateRequests.clear();
        resourceAssigner.bufAssigns.clear();
        resourceAssigner.texAssigns.clear();

        const usedBuffers = resourceAssigner.usedTransientBufs.constSlice();
        resourceAssigner.unusedTransientBufs.appendSlice(usedBuffers) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to unusedTransientBufs\n", .{});
        resourceAssigner.usedTransientBufs.clear();

        const usedTextures = resourceAssigner.usedTransientTexes.constSlice();
        resourceAssigner.unusedTransientTexes.appendSlice(usedTextures) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to unusedTransientTexes\n", .{});
        resourceAssigner.usedTransientTexes.clear();

        // TRANSIENT RESOURCES //

        // Check needed Shared Lifetimes to create or re-use existing Physical Buffer
        for (groupMerger.sharedBufLifetimes.constSlice()) |sharedBufLifetime| {
            var physCandidateIndex: ?u16 = null;
            const sharedBufDesc = resourceExtractor.bufDescriptions.getByKey(sharedBufLifetime.bufDescId.val());

            for (resourceAssigner.unusedTransientBufs.constSlice(), 0..) |transientBuf, i| {
                const transientBufDesc = resourceExtractor.bufDescriptions.getByKey(transientBuf.bufDescId.val());
                // Check if Desc Fits Existing Info
                if (bufDescEqual(&transientBufDesc, &sharedBufDesc) == true) {
                    physCandidateIndex = @intCast(i);
                    break;
                }
            }

            if (physCandidateIndex) |candidateIndex| {
                // Candidate was found -> move from unused ot used List
                var candidate = resourceAssigner.unusedTransientBufs.swapRemoveReturn(candidateIndex);
                candidate.unusedCounter = 0;
                resourceAssigner.usedTransientBufs.append(candidate) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientBufs\n", .{});
            } else {
                // Candidate not found -> create new
                const candidate = TransientBuffer{
                    .bufDescId = sharedBufLifetime.bufDescId,
                    .hardwareBuf = .{ .val = try getFreeBufId(resourceAssigner) },
                };
                try createTransientBuffer(sharedBufDesc, candidate.hardwareBuf, rendererQueue, memoryMan);
                resourceAssigner.usedTransientBufs.append(candidate) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientBufs\n", .{});
            }
        }

        // Increment unused, delete all larger than Constant
        const unusedTransientBufsLength = resourceAssigner.unusedTransientBufs.len;

        for (0..unusedTransientBufsLength) |i| {
            const index = unusedTransientBufsLength - 1 - i;
            const transientBuf = &resourceAssigner.unusedTransientBufs.buffer[index];

            if (transientBuf.unusedCounter >= rc.FRAME_BUILDS_TILL_TRANSIENT_DELETION) {
                deleteTransientBuffer(transientBuf.hardwareBuf, rendererQueue);
                resourceAssigner.unusedTransientBufs.swapRemove(@intCast(index));
            } else transientBuf.unusedCounter += 1;
        }

        // Assign Shared Transient Lifetimes to Buffers
        for (groupMerger.bufShareIndexMap.getConstItems(), 0..) |sharedIndex, i| {
            const bufRootKey = groupMerger.bufShareIndexMap.getKeyByIndex(@intCast(i));
            const bufId = resourceAssigner.usedTransientBufs.buffer[sharedIndex].hardwareBuf;

            const bufGroup = resourceMapper.bufGroupsTransient.getByKey(bufRootKey);
            // Whole Group needs to be assigned
            for (bufGroup.startMapIndex..bufGroup.endMapIndex + 1) |mapIndex| {
                const memberKey = resourceMapper.bufMapTransient.getKeyByIndex(@intCast(mapIndex));

                // Link Buffers Enum To Physical Buf ID
                if (resourceAssigner.bufAssigns.isKeyUsed(memberKey) == true) {
                    const bufName = try resourceRegistry.getBufferName(.id(memberKey));
                    std.debug.print("ERROR: 6.ResourceAssigner: Buffer Name {s} already assigned!\n", .{bufName});
                    return error.BufEnumAlreadyAssigned;
                }
                resourceAssigner.bufAssigns.upsert(memberKey, bufId);
            }
        }

        // Check needed Shared Lifetimes to create or re-use existing Physical Textures
        for (groupMerger.sharedTexLifetimes.constSlice()) |sharedTexLifetime| {
            var physCandidateIndex: ?u16 = null;
            const sharedTexDesc = resourceExtractor.texDescriptions.getByKey(sharedTexLifetime.texDescId.val());

            for (resourceAssigner.unusedTransientTexes.constSlice(), 0..) |transientTex, i| {
                const transientTexDesc = resourceExtractor.texDescriptions.getByKey(transientTex.texDescId.val());
                // Check if Desc Fits Existing Info
                if (texDescEqual(&transientTexDesc, &sharedTexDesc) == true) {
                    physCandidateIndex = @intCast(i);
                    break;
                }
            }

            if (physCandidateIndex) |candidateIndex| {
                // Candidate was found -> move from unused ot used List
                var candidate = resourceAssigner.unusedTransientTexes.swapRemoveReturn(candidateIndex);
                candidate.unusedCounter = 0;
                resourceAssigner.usedTransientTexes.append(candidate) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientTexes\n", .{});
            } else {
                // Candidate not found -> create new
                const candidate = TransientTexture{
                    .texDescId = sharedTexLifetime.texDescId,
                    .hardwareTex = .{ .val = try getFreeTexId(resourceAssigner) },
                };
                try createTransientTexture(sharedTexDesc, candidate.hardwareTex, rendererQueue, memoryMan);
                resourceAssigner.usedTransientTexes.append(candidate) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientTexes\n", .{});
            }
        }

        // Increment unused, delete all larger than Constant
        const unusedTransientTexesLength = resourceAssigner.unusedTransientTexes.len;

        for (0..unusedTransientTexesLength) |i| {
            const index = unusedTransientTexesLength - 1 - i;
            const transientTex = &resourceAssigner.unusedTransientTexes.buffer[index];

            if (transientTex.unusedCounter >= rc.FRAME_BUILDS_TILL_TRANSIENT_DELETION) {
                deleteTransientTexture(transientTex.hardwareTex, rendererQueue);
                resourceAssigner.unusedTransientTexes.swapRemove(@intCast(index));
            } else transientTex.unusedCounter += 1;
        }

        // Assign Shared Transient Lifetimes to Textures
        for (groupMerger.texShareIndexMap.getConstItems(), 0..) |sharedIndex, i| {
            const texRootKey = groupMerger.texShareIndexMap.getKeyByIndex(@intCast(i));
            const texId = resourceAssigner.usedTransientTexes.buffer[sharedIndex].hardwareTex;

            const texGroup = resourceMapper.texGroupsTransient.getByKey(texRootKey);
            // Whole Group needs to be assigned
            for (texGroup.startMapIndex..texGroup.endMapIndex + 1) |mapIndex| {
                const memberKey = resourceMapper.texMapTransient.getKeyByIndex(@intCast(mapIndex));

                // Link Textures Enum To Physical Tex ID
                if (resourceAssigner.texAssigns.isKeyUsed(memberKey) == true) {
                    const texName = try resourceRegistry.getTextureName(.id(memberKey));
                    std.debug.print("ERROR: 6.ResourceAssigner: Texture Name {s} already assigned!\n", .{texName});
                    return error.TexEnumAlreadyAssigned;
                }
                resourceAssigner.texAssigns.upsert(memberKey, texId);
            }
        }

        // PERSISTENT RESOURCES //

        // Creating, Deleting and Recreating Persistent Buffers
        for (mappingComparator.persistentBufChanges.constSlice()) |bufChanges| {
            switch (bufChanges.change) {
                .unchanged => {},
                .deleted => {
                    deleteBuffer(resourceAssigner, resourceRegistry, bufChanges.rootBuf, rendererQueue, .frameGraph);
                },
                .created => {
                    try createBuffer(resourceAssigner, resourceMapper, resourceRegistry, bufChanges.rootBuf, rendererQueue, memoryMan, .frameGraph);
                    resolveBufferUpdateRequest(resourceAssigner, bufChanges.rootBuf);
                },
                .newDesc, .newPass, .newPassAndDesc => {
                    deleteBuffer(resourceAssigner, resourceRegistry, bufChanges.rootBuf, rendererQueue, .frameGraph);
                    try createBuffer(resourceAssigner, resourceMapper, resourceRegistry, bufChanges.rootBuf, rendererQueue, memoryMan, .frameGraph);
                    resolveBufferUpdateRequest(resourceAssigner, bufChanges.rootBuf);
                },
            }
        }

        // Creating, Deleting and Recreating Persistent Textures
        for (mappingComparator.persistentTexChanges.constSlice()) |texChanges| {
            switch (texChanges.change) {
                .unchanged => {},
                .deleted => {
                    deleteTexture(resourceAssigner, resourceRegistry, texChanges.rootTex, rendererQueue, .frameGraph);
                },
                .created => {
                    try createTexture(resourceAssigner, resourceMapper, resourceRegistry, texChanges.rootTex, rendererQueue, memoryMan, .frameGraph);
                    resolveTextureUpdateRequest(resourceAssigner, texChanges.rootTex);
                },
                .newDesc, .newPass, .newPassAndDesc => {
                    deleteTexture(resourceAssigner, resourceRegistry, texChanges.rootTex, rendererQueue, .frameGraph);
                    try createTexture(resourceAssigner, resourceMapper, resourceRegistry, texChanges.rootTex, rendererQueue, memoryMan, .frameGraph);
                    resolveTextureUpdateRequest(resourceAssigner, texChanges.rootTex);
                },
            }
        }

        if (rc.FRAME_GRAPH_DEBUG) std.debug.print("\n", .{});

        // Create Manuel Buffer Assignments
        for (resourceAssigner.manualBufs.getConstItems(), 0..) |bufInf, i| {
            const enumKey = resourceAssigner.manualBufs.getKeyByIndex(@intCast(i));
            resourceAssigner.bufAssigns.upsert(enumKey, bufInf.id);
        }

        // Create Persistent Buffer Assignments
        for (resourceMapper.bufGroupsPersistent.getConstItems()) |bufGroup| {
            const rootBufKey = bufGroup.rootBuf.val();
            const rootBufPhysicalId = resourceAssigner.rootBufPhysicalMap.getByKey(rootBufKey);

            for (bufGroup.startMapIndex..bufGroup.endMapIndex + 1) |mapIndex| {
                const bufEnumKey = resourceMapper.bufMapPersistent.getKeyByIndex(@intCast(mapIndex));

                // Link Buffer Pass ID To Physical Buf ID
                if (resourceAssigner.bufAssigns.isKeyUsed(bufEnumKey) == true) {
                    const bufName = try resourceRegistry.getBufferName(bufGroup.rootBuf);
                    std.debug.print("ERROR: 6.ResourceAssigner: Buffer {s} already assigned!\n", .{bufName});
                    return error.BufEnumAlreadyAssigned;
                }
                resourceAssigner.bufAssigns.upsert(bufEnumKey, rootBufPhysicalId.id);
            }
        }

        // Create Manuel Texture Assignments
        for (resourceAssigner.manualTexes.getConstItems(), 0..) |texInf, i| {
            const enumKey = resourceAssigner.manualTexes.getKeyByIndex(@intCast(i));
            resourceAssigner.texAssigns.upsert(enumKey, texInf.id);
        }

        // Create Persistent Texture Assignment
        for (resourceMapper.texGroupsPersistent.getConstItems()) |texGroup| {
            const rootTexKey = texGroup.rootTex;
            const rootTexPhysicalId = resourceAssigner.rootTexPhysicalMap.getByKey(rootTexKey.val());

            for (texGroup.startMapIndex..texGroup.endMapIndex + 1) |mapIndex| {
                const texEnumkey = resourceMapper.texMapPersistent.getKeyByIndex(@intCast(mapIndex));

                // Link Texture Pass ID To Physical Tex ID
                if (resourceAssigner.texAssigns.isKeyUsed(texEnumkey) == true) {
                    const texName = try resourceRegistry.getTextureName(texGroup.rootTex);
                    std.debug.print("ERROR: 6.ResourceAssigner: Texture {s} already assigned!\n", .{texName});
                    return error.BufEnumAlreadyAssigned;
                }
                resourceAssigner.texAssigns.upsert(texEnumkey, rootTexPhysicalId.id);
            }
        }

        // Debug
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("6.ResourceAssigner\n", .{});
            // Transient Buffer View:
            for (resourceAssigner.usedTransientBufs.constSlice(), 0..) |transientBuf, i| {
                std.debug.print(" - Transient Buf {} -> (BufId {}) (unused for {} Builds)\n", .{ i, transientBuf.hardwareBuf, transientBuf.unusedCounter });
            }
            std.debug.print("\n", .{});
            // Transient Texture View:
            for (resourceAssigner.usedTransientTexes.constSlice(), 0..) |transientTex, i| {
                std.debug.print(" - Transient Tex {} -> (TexId {}) (unused for {} Builds)\n", .{ i, transientTex.hardwareTex, transientTex.unusedCounter });
            }
            std.debug.print("\n", .{});
            // Buffers
            for (resourceAssigner.bufAssigns.getConstItems(), 0..) |bufId, i| {
                const bufKey = resourceAssigner.bufAssigns.getKeyByIndex(@intCast(i));
                const bufName = try resourceRegistry.getBufferName(.id(bufKey));
                std.debug.print(" - Buf {s} assigned -> BufId{}\n", .{ bufName, bufId });
            }
            std.debug.print("\n", .{});
            // Textures
            for (resourceAssigner.texAssigns.getConstItems(), 0..) |texId, i| {
                const texKey = resourceAssigner.texAssigns.getKeyByIndex(@intCast(i));
                const texName = try resourceRegistry.getTextureName(.id(texKey));
                std.debug.print(" - Tex {s} assigned -> TexId{}\n", .{ texName, texId });
            }
            std.debug.print("\n", .{});
        }
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
        resourceAssigner: *ResourceAssignerData,
        resourceMapper: *const ResourceMapperData,
        resourceRegistry: *const ResourceRegistryData,
        bufPassId: BufPassId,
        rendererQueue: *RendererQueue,
        memoryMan: *MemoryManager,
        authority: enum { frameGraph, manuel },
    ) !void {
        // Add Physical Assignment
        const bufId = try getFreeBufId(resourceAssigner);
        const rootBufKey = bufPassId.val();

        const bufDesc = switch (authority) {
            .frameGraph => resourceMapper.bufGroupsPersistent.getByKey(rootBufKey).bufDesc,
            .manuel => try resourceRegistry.getBufferDefinition(bufPassId),
        };

        const bufInf = BufInf{
            .id = .{ .val = bufId },
            .mem = bufDesc.mem,
            .elementSize = bufDesc.elementSize,
            .len = bufDesc.len,
            .typ = bufDesc.typ,
            .update = bufDesc.update,
            .resize = bufDesc.resize,
        };

        switch (authority) {
            .frameGraph => resourceAssigner.rootBufPhysicalMap.upsert(rootBufKey, bufInf),
            .manuel => {
                resourceAssigner.manualBufs.upsert(rootBufKey, bufInf);
                resourceAssigner.bufAssigns.upsert(rootBufKey, bufInf.id);
            },
        }

        // RENDERER QUEUE SEND CREATE (AND UPDATE!) (Stop Renderer?)
        const arena = memoryMan.getGlobalArena();
        const AddBufPtr = @FieldType(RendererQueue.RendererEvent, "addBuffer");
        const AddBuf = std.meta.Child(AddBufPtr);
        const bufferPtr = try arena.create(AddBuf);
        bufferPtr.* = .{ .bufInf = bufInf, .data = null };
        rendererQueue.append(.{ .addBuffer = bufferPtr });

        const rootBufName = try resourceRegistry.getBufferName(bufPassId);
        std.debug.print("6.Resource Assigner: Root Buf {s} (BufId {}) Creation send to Renderer\n", .{ rootBufName, bufId });
    }

    pub fn deleteBuffer(
        resourceAssigner: *ResourceAssignerData,
        resourceRegistry: *const ResourceRegistryData,
        bufPassId: BufPassId,
        rendererQueue: *RendererQueue,
        authority: enum { frameGraph, manuel },
    ) void {
        // Remove Physical Assignment
        const rootBufKey = bufPassId.val();

        const isUsed = switch (authority) {
            .frameGraph => resourceAssigner.rootBufPhysicalMap.isKeyUsed(rootBufKey),
            .manuel => resourceAssigner.manualBufs.isKeyUsed(rootBufKey),
        };

        if (isUsed == false) {
            const bufName = resourceRegistry.getBufferName(bufPassId) catch undefined;
            std.debug.print("ERROR: 6.ResourceAssigner: Buffer {s} Authority {s} no Physical ID -> cant be destroyed!\n", .{ bufName, @tagName(authority) });
            return;
        }

        const bufInf = switch (authority) {
            .frameGraph => resourceAssigner.rootBufPhysicalMap.getByKey(rootBufKey),
            .manuel => resourceAssigner.manualBufs.getByKey(rootBufKey),
        };
        freeUpBufId(resourceAssigner, bufInf.id.val);

        switch (authority) {
            .frameGraph => resourceAssigner.rootBufPhysicalMap.remove(rootBufKey),
            .manuel => resourceAssigner.manualBufs.remove(rootBufKey),
        }

        // RENDERER QUEUE SEND DELETE (Stop Renderer missing?)
        rendererQueue.append(.{ .removeBuffer = bufInf.id });

        const rootBufName = resourceRegistry.getBufferName(bufPassId) catch "UNKNOWN";
        std.debug.print("6.Resource Assigner: Root Buf {s} (BufId {}) Deletion send to Renderer\n", .{ rootBufName, bufInf.id.val });
    }

    pub fn createTexture(
        resourceAssigner: *ResourceAssignerData,
        resourceMapper: *const ResourceMapperData,
        resourceRegistry: *const ResourceRegistryData,
        texPassId: TexPassId,
        rendererQueue: *RendererQueue,
        memoryMan: *MemoryManager,
        authority: enum { frameGraph, manuel },
    ) !void {
        // Add Physical Assignment
        const texId = try getFreeTexId(resourceAssigner);
        const rootTexKey = texPassId.val();

        const texDesc = switch (authority) {
            .frameGraph => resourceMapper.texGroupsPersistent.getByKey(rootTexKey).texDesc,
            .manuel => try resourceRegistry.getTextureDefinition(texPassId),
        };

        const texInf = TexInf{
            .id = .{ .val = texId },
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
            .frameGraph => resourceAssigner.rootTexPhysicalMap.upsert(rootTexKey, texInf),
            .manuel => {
                resourceAssigner.manualTexes.upsert(rootTexKey, texInf);
                resourceAssigner.texAssigns.upsert(rootTexKey, texInf.id);
            },
        }

        // RENDERER QUEUE SEND CREATE (AND UPDATE!) (Stop Renderer?)
        const arena = memoryMan.getGlobalArena();
        const AddTexPtr = @FieldType(RendererQueue.RendererEvent, "addTexture");
        const AddTex = std.meta.Child(AddTexPtr);
        const addTextureDataPtr = try arena.create(AddTex);
        addTextureDataPtr.* = .{ .texInf = texInf, .data = null };
        rendererQueue.append(.{ .addTexture = addTextureDataPtr });

        const rootBufName = try resourceRegistry.getTextureName(texPassId);
        std.debug.print("6.Resource Assigner: Root Tex {s} (TexId {}) Creation send to Renderer\n", .{ rootBufName, texId });
    }

    pub fn deleteTexture(
        resourceAssigner: *ResourceAssignerData,
        resourceRegistry: *const ResourceRegistryData,
        texPassId: TexPassId,
        rendererQueue: *RendererQueue,
        authority: enum { frameGraph, manuel },
    ) void {
        // Remove Physical Assignment
        const rootTexKey = texPassId.val();

        const isUsed = switch (authority) {
            .frameGraph => resourceAssigner.rootTexPhysicalMap.isKeyUsed(rootTexKey),
            .manuel => resourceAssigner.manualTexes.isKeyUsed(rootTexKey),
        };

        if (isUsed == false) {
            const texName = resourceRegistry.getTextureName(texPassId) catch undefined;
            std.debug.print("ERROR: 6.ResourceAssigner: Texture {s} Authority {s} no Physical ID -> cant be destroyed!\n", .{ texName, @tagName(authority) });
            return;
        }

        const texInf = switch (authority) {
            .frameGraph => resourceAssigner.rootTexPhysicalMap.getByKey(rootTexKey),
            .manuel => resourceAssigner.manualTexes.getByKey(rootTexKey),
        };
        freeUpTexId(resourceAssigner, texInf.id.val);

        switch (authority) {
            .frameGraph => resourceAssigner.rootTexPhysicalMap.remove(rootTexKey),
            .manuel => resourceAssigner.manualTexes.remove(rootTexKey),
        }

        // RENDERER QUEUE SEND DELETE (Stop Renderer missing?)
        rendererQueue.append(.{ .removeTexture = texInf.id });

        const rootBufName = resourceRegistry.getTextureName(texPassId) catch "UNKNOWN";
        std.debug.print("6.Resource Assigner: Root Tex {s} (TexId {}) Deletion send to Renderer\n", .{ rootBufName, texInf.id.val });
    }

    pub fn getFreeBufId(resourceAssigner: *ResourceAssignerData) !u16 {
        return if (resourceAssigner.bufIdPool.isFull() == false) resourceAssigner.bufIdPool.reserveKey() else error.BufIdsFullyUsed;
    }

    pub fn freeUpBufId(resourceAssigner: *ResourceAssignerData, bufIdVal: u16) void {
        resourceAssigner.bufIdPool.freeKey(bufIdVal);
    }

    pub fn getFreeTexId(resourceAssigner: *ResourceAssignerData) !u16 {
        return if (resourceAssigner.texIdPool.isFull() == false) resourceAssigner.texIdPool.reserveKey() else error.TexIdsFullyUsed;
    }

    pub fn freeUpTexId(resourceAssigner: *ResourceAssignerData, texIdVal: u16) void {
        resourceAssigner.texIdPool.freeKey(texIdVal);
    }

    pub fn resolveBufferUpdateRequest(resourceAssigner: *ResourceAssignerData, bufPassId: BufPassId) void {
        const updateRequest: ?pe.UpdateRequestEnum = switch (bufPassId.val()) {
            rc.MainCamUB.val() => .CamMainUpdate,
            rc.DebugCamUB.val() => .CanDebugUpdate,
            rc.ImguiIB.val() => .GuiUpdate,
            rc.ImguiVB.val() => .GuiUpdate,
            rc.EntitySB.val() => .EntityUpdate,
            else => null,
        };
        if (updateRequest) |request| resourceAssigner.updateRequests.upsert(@intFromEnum(request), request);
    }

    pub fn resolveTextureUpdateRequest(resourceAssigner: *ResourceAssignerData, texPassId: TexPassId) void {
        const updateRequest: ?pe.UpdateRequestEnum = switch (texPassId.val()) {
            rc.TestTileTex.val() => .TestTileUpdate,
            rc.ImguiFontTex.val() => .GuiUpdate,
            else => null,
        };
        if (updateRequest) |request| {
            resourceAssigner.updateRequests.upsert(@intFromEnum(request), request);
        }
    }
};

fn bufDescEqual(bufDesc1: *const BufDesc, bufDesc2: *const BufDesc) bool {
    return std.meta.eql(bufDesc1.*, bufDesc2.*);
}

fn texDescEqual(texDesc1: *const TexDesc, texDesc2: *const TexDesc) bool {
    return std.meta.eql(texDesc1.*, texDesc2.*);
}

// - WHAT ABOUT INDIRECT DEPENDENCIES? (SPLITTING INTO OUTPUT PASSES AND ALL PASSES? SPLITTING GLOBAL PASSES AND INSTANCE PASSES?)
// - WHAT ABOUT RESIZES?
