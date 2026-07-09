const EngineData = @import("../EngineData.zig").EngineData;
const UiData = @import("../ui/UiData.zig").UiData;
const ic = @import("../.configs/idConfig.zig");

const TexDesc = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const TransientTexture = @import("../renderGraph/components.zig").TransientTexture;
const BufDesc = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const TransientBuffer = @import("../renderGraph/components.zig").TransientBuffer;
const TextureMeta = @import("../render/types/res/TextureMeta.zig").TextureMeta;
const BufferMeta = @import("../render/types/res/BufferMeta.zig").BufferMeta;
const RendererQueue = @import("../render/RendererQueue.zig").RendererQueue;
const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const TexId = @import("../.configs/idConfig.zig").TexId;
const BufId = @import("../.configs/idConfig.zig").BufId;
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");
const TexInf = TextureMeta.TexInf;
const BufInf = BufferMeta.BufInf;

const getResTyp = @import("../renderGraph/components.zig").getResTyp;
const texToRes = @import("../renderGraph/components.zig").texToRes;
const bufToRes = @import("../renderGraph/components.zig").bufToRes;
const resToBuf = @import("../renderGraph/components.zig").resToBuf;
const resToTex = @import("../renderGraph/components.zig").resToTex;

const MapperData = @import("../renderGraph/5.1_Mapper/MapperData.zig").MapperData;
const ComparatorData = @import("../renderGraph/5.3_Comparator/ComparatorData.zig").ComparatorData;
const GroupData = @import("../renderGraph/5.4_Group/GroupData.zig").GroupData;

const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const RenderAssignerData = @import("../renderAssigner/RenderAssignerData.zig").RenderAssignerData;
const RenderAssignerQueue = @import("../renderAssigner/RenderAssignerQueue.zig").RenderAssignerQueue;
const RenderGraphData = @import("../renderGraph/RenderGraphData.zig").RenderGraphData;

pub const RenderAssignerSys = struct {
    pub fn assign(self: *RenderAssignerData, renderGraph: *const RenderGraphData, registry: *const RenderRegistryData, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        const mapper = &renderGraph.mapper;
        const comparator = &renderGraph.comparator;
        const groups = &renderGraph.group;

        // Resets
        self.bufAssigns.clear();
        self.texAssigns.clear();

        self.unusedTransientBufs.appendSliceAssumeCapacity(self.usedTransientBufs.constSlice());
        self.unusedTransientTexes.appendSliceAssumeCapacity(self.usedTransientTexes.constSlice());

        self.usedTransientBufs.clear();
        self.usedTransientTexes.clear();

        // Buffer Pooling
        for (groups.sharedBufLifetimes.constSlice()) |sharedBufLifetime| {
            const desc = mapper.transientGroups.getByKey(sharedBufLifetime.resKey).desc;
            var candidateIndex: ?u16 = null;

            for (self.unusedTransientBufs.constSlice(), 0..) |transientBuf, i| {
                if (bufDescEqual(&transientBuf.bufDesc, &desc.bufDesc)) {
                    candidateIndex = @intCast(i);
                    break;
                }
            }
            if (candidateIndex) |index| {
                var candidate = self.unusedTransientBufs.swapRemoveReturn(index);
                candidate.unusedCounter = 0;
                self.usedTransientBufs.append(candidate) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientBufs\n", .{});
            } else {
                const candidate = TransientBuffer{ .bufDesc = desc.bufDesc, .hardwareBuf = try getFreeBufId(self) };
                try createTransientBuffer(desc.bufDesc, candidate.hardwareBuf, rendererQueue, memoryMan);
                self.usedTransientBufs.append(candidate) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientBufs\n", .{});
            }
        }

        // Texture Pooling
        for (groups.sharedTexLifetimes.constSlice()) |sharedTexLifetime| {
            const desc = mapper.transientGroups.getByKey(sharedTexLifetime.resKey).desc;
            var candidateIndex: ?u16 = null;

            for (self.unusedTransientTexes.constSlice(), 0..) |transientTex, i| {
                if (texDescEqual(&transientTex.texDesc, &desc.texDesc)) {
                    candidateIndex = @intCast(i);
                    break;
                }
            }
            if (candidateIndex) |index| {
                var candidate = self.unusedTransientTexes.swapRemoveReturn(index);
                candidate.unusedCounter = 0;
                self.usedTransientTexes.append(candidate) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientTexes\n", .{});
            } else {
                const candidate = TransientTexture{ .texDesc = desc.texDesc, .hardwareTex = try getFreeTexId(self) };
                try createTransientTexture(desc.texDesc, candidate.hardwareTex, rendererQueue, memoryMan);
                self.usedTransientTexes.append(candidate) catch std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientTexes\n", .{});
            }
        }

        // Assignments
        for (groups.bufShareIndexMap.getConstItems(), 0..) |sharedIndex, i| {
            const rootRes = groups.bufShareIndexMap.getKeyByIndex(@intCast(i));
            const group = mapper.transientGroups.getByKey(bufToRes(rootRes));

            const bufHardwareId = self.usedTransientBufs.buffer[sharedIndex].hardwareBuf;

            for (group.firstMapIndex..group.lastMapIndex + 1) |mapIndex| {
                const memeberRes = mapper.transientMap.getKeyByIndex(@intCast(mapIndex));
                const bufPassId: BufPassId = resToBuf(memeberRes);

                if (self.bufAssigns.isKeyUsed(bufPassId)) {
                    const bufName = try registry.getBufferName(bufPassId);
                    std.debug.print("ERROR: 6.ResourceAssigner: Buffer Name {s} already assigned!\n", .{bufName});
                    return error.BufEnumAlreadyAssigned;
                }
                self.bufAssigns.upsert(bufPassId, bufHardwareId);
            }
        }

        for (groups.texShareIndexMap.getConstItems(), 0..) |sharedIndex, i| {
            const rootRes = groups.texShareIndexMap.getKeyByIndex(@intCast(i));
            const group = mapper.transientGroups.getByKey(texToRes(rootRes));

            const texHardwareId = self.usedTransientTexes.buffer[sharedIndex].hardwareTex;

            for (group.firstMapIndex..group.lastMapIndex + 1) |mapIndex| {
                const memberRes = mapper.transientMap.getKeyByIndex(@intCast(mapIndex));
                const texPassId: TexPassId = resToTex(memberRes);

                if (self.texAssigns.isKeyUsed(texPassId)) {
                    const texName = try registry.getTextureName(texPassId);
                    std.debug.print("ERROR: 6.ResourceAssigner: Texture Name {s} already assigned!\n", .{texName});
                    return error.TexEnumAlreadyAssigned;
                }
                self.texAssigns.upsert(texPassId, texHardwareId);
            }
        }

        // Cleanup Buffers
        const unusedBufsLen = self.unusedTransientBufs.len;
        for (0..unusedBufsLen) |i| {
            const index = unusedBufsLen - 1 - i;
            const transientBuf = &self.unusedTransientBufs.buffer[index];

            if (transientBuf.unusedCounter >= rc.FRAME_BUILDS_TILL_TRANSIENT_DELETION) {
                deleteTransientBuffer(transientBuf.hardwareBuf, rendererQueue);
                freeUpBufId(self, transientBuf.hardwareBuf);
                self.unusedTransientBufs.swapRemove(@intCast(index));
            } else {
                transientBuf.unusedCounter += 1;
            }
        }

        // Cleanup Textures
        const unusedTexesLen = self.unusedTransientTexes.len;
        for (0..unusedTexesLen) |i| {
            const index = unusedTexesLen - 1 - i;
            const transientTex = &self.unusedTransientTexes.buffer[index];

            if (transientTex.unusedCounter >= rc.FRAME_BUILDS_TILL_TRANSIENT_DELETION) {
                deleteTransientTexture(transientTex.hardwareTex, rendererQueue);
                freeUpTexId(self, transientTex.hardwareTex);
                self.unusedTransientTexes.swapRemove(@intCast(index));
            } else {
                transientTex.unusedCounter += 1;
            }
        }

        // PERSISTENT RESOURCES //

        // Creating, Deleting and Recreating Persistent Resources
        for (comparator.persistentChanges.constSlice()) |groupChange| {
            const rootKey = groupChange.rootResource;
            const keyTyp = getResTyp(rootKey);

            switch (groupChange.change) {
                .unchanged, .newPass => {},
                .deleted => switch (keyTyp) {
                    .Buf => {
                        if (self.manualBufs.isKeyUsed(resToBuf(rootKey))) continue;

                        try deferBufferDeletion(self, resToBuf(rootKey)); // or deleteBuffer
                    },
                    .Tex => {
                        if (self.manualTexes.isKeyUsed(resToTex(rootKey))) continue;

                        try deferTextureDeletion(self, resToTex(rootKey)); // or deleteTexture
                    },
                },
                .created => switch (keyTyp) {
                    .Buf => {
                        if (self.manualBufs.isKeyUsed(resToBuf(rootKey))) continue;

                        try createBuffer(self, mapper, registry, resToBuf(rootKey), rendererQueue, memoryMan);
                    },
                    .Tex => {
                        if (self.manualTexes.isKeyUsed(resToTex(rootKey))) continue;

                        try createTexture(self, mapper, registry, resToTex(rootKey), rendererQueue, memoryMan);
                    },
                },
                .newDesc, .newPassAndDesc => switch (keyTyp) {
                    .Buf => {
                        if (self.manualBufs.isKeyUsed(resToBuf(rootKey))) {
                            const bufName = try registry.getBufferName(resToBuf(rootKey));
                            std.debug.print("WARN: desc changed on manual Buffer! {s} -> graph wont recreate\n", .{bufName});
                            continue;
                        }

                        try deferBufferDeletion(self, resToBuf(rootKey)); // or deleteBuffer
                        try createBuffer(self, mapper, registry, resToBuf(rootKey), rendererQueue, memoryMan);
                    },
                    .Tex => {
                        if (self.manualTexes.isKeyUsed(resToTex(rootKey))) {
                            const texName = try registry.getTextureName(resToTex(rootKey));
                            std.debug.print("WARN: desc changed on manual Texture! {s} -> graph wont recreate\n", .{texName});
                            continue;
                        }

                        try deferTextureDeletion(self, resToTex(rootKey)); // or deleteTexture
                        try createTexture(self, mapper, registry, resToTex(rootKey), rendererQueue, memoryMan);
                    },
                },
            }
        }

        if (rc.FRAME_GRAPH_DEBUG) std.debug.print("\n", .{});

        for (mapper.persistentGroups.getConstItems(), 0..) |group, i| {
            const rootKey = mapper.persistentGroups.getKeyByIndex(@intCast(i));

            switch (getResTyp(rootKey)) {
                .Buf => {
                    const isManual = self.manualBufs.isKeyUsed(resToBuf(rootKey));
                    const bufId = if (isManual) self.manualBufs.getByKey(resToBuf(rootKey)).id else self.rootBufPhysicalMap.getByKey(resToBuf(rootKey));

                    for (group.firstMapIndex..group.lastMapIndex + 1) |mapIndex| {
                        const memberKey = mapper.persistentMap.getKeyByIndex(@intCast(mapIndex));
                        const bufPassId = resToBuf(memberKey);

                        if (self.bufAssigns.isKeyUsed(bufPassId)) {
                            const bufName = try registry.getBufferName(bufPassId);
                            std.debug.print("ERROR: 6.ResourceAssigner: Buffer {s} already assigned!\n", .{bufName});
                            return error.BufEnumAlreadyAssigned;
                        }
                        self.bufAssigns.upsert(bufPassId, bufId);
                    }
                },
                .Tex => {
                    const isManual = self.manualTexes.isKeyUsed(resToTex(rootKey));
                    const texId = if (isManual) self.manualTexes.getByKey(resToTex(rootKey)).id else self.rootTexPhysicalMap.getByKey(resToTex(rootKey));

                    for (group.firstMapIndex..group.lastMapIndex + 1) |mapIndex| {
                        const memberKey = mapper.persistentMap.getKeyByIndex(@intCast(mapIndex));
                        const texPassId = resToTex(memberKey);

                        if (self.texAssigns.isKeyUsed(texPassId)) {
                            const texName = try registry.getTextureName(texPassId);
                            std.debug.print("ERROR: 6.ResourceAssigner: Texture {s} already assigned!\n", .{texName});
                            return error.TexEnumAlreadyAssigned;
                        }
                        self.texAssigns.upsert(texPassId, texId);
                    }
                },
            }
        }

        // Create Manuel Texture Assignments
        for (self.manualTexes.getConstItems(), 0..) |texInf, i| {
            const texPassId = self.manualTexes.getKeyByIndex(@intCast(i));
            self.texAssigns.upsert(texPassId, texInf.id);
        }

        // Create Manuel Buffer Assignments
        for (self.manualBufs.getConstItems(), 0..) |bufInf, i| {
            const enumKey = self.manualBufs.getKeyByIndex(@intCast(i));
            self.bufAssigns.upsert(enumKey, bufInf.id);
        }

        // Deferred Persistent Textures Deletion
        const pendingTexLen = self.pendingTexDeletions.len;
        for (0..pendingTexLen) |i| {
            const index = pendingTexLen - 1 - i;
            const pending = &self.pendingTexDeletions.buffer[index];

            if (pending.unusedCounter >= rc.FRAME_BUILDS_TILL_TRANSIENT_DELETION) {
                rendererQueue.append(.{ .removeTexture = pending.id });
                freeUpTexId(self, pending.id);
                self.pendingTexDeletions.swapRemove(@intCast(index));
            } else pending.unusedCounter += 1;
        }

        // Deferred Persistent Buffers Deletion
        const pendingBufLen = self.pendingBufDeletions.len;
        for (0..pendingBufLen) |i| {
            const index = pendingBufLen - 1 - i;
            const pending = &self.pendingBufDeletions.buffer[index];

            if (pending.unusedCounter >= rc.FRAME_BUILDS_TILL_TRANSIENT_DELETION) {
                rendererQueue.append(.{ .removeBuffer = pending.id });
                freeUpBufId(self, pending.id);
                self.pendingBufDeletions.swapRemove(@intCast(index));
            } else pending.unusedCounter += 1;
        }

        // Debug
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("6.ResourceAssigner\n", .{});
            for (self.usedTransientBufs.constSlice(), 0..) |buf, i| {
                std.debug.print(" - Transient Buf {} -> Buf (BufId {}) (unused for {} Builds)\n", .{ i, buf.hardwareBuf.val(), buf.unusedCounter });
            }
            for (self.usedTransientTexes.constSlice(), 0..) |tex, i| {
                std.debug.print(" - Transient Tex {} -> Tex (TexId {}) (unused for {} Builds)\n", .{ i, tex.hardwareTex.val(), tex.unusedCounter });
            }
            std.debug.print("\n", .{});
            // Buffers
            for (self.bufAssigns.getConstItems(), 0..) |bufId, i| {
                const bufPassId = self.bufAssigns.getKeyByIndex(@intCast(i));
                const bufName = try registry.getBufferName(bufPassId);
                std.debug.print(" - Buf {s} assigned -> BufId {}\n", .{ bufName, bufId.val() });
            }
            std.debug.print("\n", .{});
            // Textures
            for (self.texAssigns.getConstItems(), 0..) |texId, i| {
                const texPassId = self.texAssigns.getKeyByIndex(@intCast(i));
                const texName = try registry.getTextureName(texPassId);
                std.debug.print(" - Tex {s} assigned -> TexId {}\n", .{ texName, texId.val() });
            }
            std.debug.print("\n", .{});
        }
    }

    pub fn deferTextureDeletion(resourceAssigner: *RenderAssignerData, rootTexId: TexPassId) !void {
        if (resourceAssigner.rootTexPhysicalMap.isKeyUsed(rootTexId) == false) return error.rootTexKeyNotUsed;
        const texId = resourceAssigner.rootTexPhysicalMap.getByKey(rootTexId);
        resourceAssigner.rootTexPhysicalMap.remove(rootTexId);
        resourceAssigner.pendingTexDeletions.append(.{ .id = texId }) catch std.debug.print("ERROR: 6.ResourceAssigner: pendingTexDeletions append failed\n", .{});
    }

    pub fn deferBufferDeletion(resourceAssigner: *RenderAssignerData, rootBufId: BufPassId) !void {
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

    pub fn createBufferManuel(assignerData: *RenderAssignerData, registry: *const RenderRegistryData, rootBuf: BufPassId, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        if (assignerData.rootBufPhysicalMap.isKeyUsed(rootBuf)) return error.GraphAlreadyOwnsBuffer;

        const bufId = try getFreeBufId(assignerData);
        const bufDesc = try registry.getBufferDefinition(rootBuf);
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

        const rootBufName = try registry.getBufferName(rootBuf);
        std.debug.print("6.Resource Assigner: Root Buf {s} (BufId {}) Creation send to Renderer\n", .{ rootBufName, bufId });
    }

    pub fn createBuffer(
        assignerData: *RenderAssignerData,
        mapperData: *const MapperData,
        registry: *const RenderRegistryData,
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

        const rootBufName = try registry.getBufferName(rootBuf);
        std.debug.print("6.Resource Assigner: Root Buf {s} (BufId {}) Creation send to Renderer\n", .{ rootBufName, bufId });
    }

    pub fn deleteBufferManuel(assignerData: *RenderAssignerData, registry: *const RenderRegistryData, rootBufKey: BufPassId, rendererQueue: *RendererQueue) void {
        const isUsed = assignerData.manualBufs.isKeyUsed(rootBufKey);
        if (isUsed == false) {
            const bufName = registry.getBufferName(rootBufKey) catch undefined;
            std.debug.print("ERROR: 6.ResourceAssigner: Buffer {s} no Physical ID -> cant be destroyed!\n", .{bufName});
            return;
        }
        const bufId = assignerData.manualBufs.getByKey(rootBufKey).id;
        freeUpBufId(assignerData, bufId);
        assignerData.manualBufs.remove(rootBufKey);
        rendererQueue.append(.{ .removeBuffer = bufId }); // (Stop Renderer missing?)

        const rootBufName = registry.getBufferName(rootBufKey) catch "UNKNOWN";
        std.debug.print("6.Resource Assigner: Root Buf {s} (BufId {}) Deletion send to Renderer\n", .{ rootBufName, bufId.val() });
    }

    pub fn deleteBuffer(assignerData: *RenderAssignerData, registry: *const RenderRegistryData, rootBufKey: BufPassId, rendererQueue: *RendererQueue) void {
        const isUsed = assignerData.rootBufPhysicalMap.isKeyUsed(rootBufKey);
        if (isUsed == false) {
            const bufName = registry.getBufferName(rootBufKey) catch undefined;
            std.debug.print("ERROR: 6.ResourceAssigner: Buffer {s} no Physical ID -> cant be destroyed!\n", .{bufName});
            return;
        }
        const bufId = assignerData.rootBufPhysicalMap.getByKey(rootBufKey).id;
        freeUpBufId(assignerData, bufId);
        assignerData.rootBufPhysicalMap.remove(rootBufKey);
        rendererQueue.append(.{ .removeBuffer = bufId }); // (Stop Renderer missing?)

        const rootBufName = registry.getBufferName(rootBufKey) catch "UNKNOWN";
        std.debug.print("6.Resource Assigner: Root Buf {s} (BufId {}) Deletion send to Renderer\n", .{ rootBufName, bufId.val() });
    }

    pub fn createTextureManuel(assignerData: *RenderAssignerData, registry: *const RenderRegistryData, rootTex: TexPassId, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        if (assignerData.rootTexPhysicalMap.isKeyUsed(rootTex)) return error.GraphAlreadyOwnsTexture;

        const texId = try getFreeTexId(assignerData);
        const texDesc = try registry.getTextureDefinition(rootTex);
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

        const rootBufName = try registry.getTextureName(rootTex);
        std.debug.print("6.Resource Assigner: Root Tex {s} (TexId {}) Creation send to Renderer\n", .{ rootBufName, texId });
    }

    pub fn createTexture(
        assignerData: *RenderAssignerData,
        mapperData: *const MapperData,
        registry: *const RenderRegistryData,
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

        const rootBufName = try registry.getTextureName(rootTex);
        std.debug.print("6.Resource Assigner: Root Tex {s} (TexId {}) Creation send to Renderer\n", .{ rootBufName, texId });
    }

    pub fn deleteTextureManuel(assignerData: *RenderAssignerData, registry: *const RenderRegistryData, rootTexId: TexPassId, rendererQueue: *RendererQueue) void {
        const isUsed = assignerData.manualTexes.isKeyUsed(rootTexId);
        if (isUsed == false) {
            const texName = registry.getTextureName(rootTexId) catch undefined;
            std.debug.print("ERROR: 6.ResourceAssigner: Texture {s} no Physical ID -> cant be destroyed!\n", .{texName});
            return;
        }
        const texInf = assignerData.manualTexes.getByKey(rootTexId);
        freeUpTexId(assignerData, texInf.id);

        assignerData.manualTexes.remove(rootTexId);
        rendererQueue.append(.{ .removeTexture = texInf.id }); // (Stop Renderer missing?)

        const rootBufName = registry.getTextureName(rootTexId) catch "UNKNOWN";
        std.debug.print("6.Resource Assigner: Root Tex {s} (TexId {}) Deletion send to Renderer\n", .{ rootBufName, texInf.id.val() });
    }

    pub fn deleteTexture(assignerData: *RenderAssignerData, registry: *const RenderRegistryData, rootTexId: TexPassId, rendererQueue: *RendererQueue) void {
        const isUsed = assignerData.rootTexPhysicalMap.isKeyUsed(rootTexId);
        if (isUsed == false) {
            const texName = registry.getTextureName(rootTexId) catch undefined;
            std.debug.print("ERROR: 6.ResourceAssigner: Texture {s} no Physical ID -> cant be destroyed!\n", .{texName});
            return;
        }
        const texInf = assignerData.rootTexPhysicalMap.getByKey(rootTexId);
        freeUpTexId(assignerData, texInf.id);

        assignerData.rootTexPhysicalMap.remove(rootTexId);
        rendererQueue.append(.{ .removeTexture = texInf.id }); // (Stop Renderer missing?)

        const rootBufName = registry.getTextureName(rootTexId) catch "UNKNOWN";
        std.debug.print("6.Resource Assigner: Root Tex {s} (TexId {}) Deletion send to Renderer\n", .{ rootBufName, texInf.id.val() });
    }

    pub fn getFreeBufId(assignerData: *RenderAssignerData) !BufId {
        const bufKey = assignerData.bufIdPool.tryReserveKey() orelse return error.BufIdsFullyUsed;
        return .id(bufKey);
    }

    pub fn freeUpBufId(assignerData: *RenderAssignerData, bufId: BufId) void {
        assignerData.bufIdPool.freeKey(bufId.val());
    }

    pub fn getFreeTexId(assignerData: *RenderAssignerData) !TexId {
        const texKey = assignerData.texIdPool.tryReserveKey() orelse return error.TexIdsFullyUsed;
        return .id(texKey);
    }

    pub fn freeUpTexId(assignerData: *RenderAssignerData, texId: TexId) void {
        assignerData.texIdPool.freeKey(texId.val());
    }

    // ASSIGNER FN END //

    pub fn createTextureManually(frameGraph: *RenderAssignerData, registry: *const RenderRegistryData, texPassId: TexPassId, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        try createTextureManuel(frameGraph, registry, texPassId, rendererQueue, memoryMan);
    }

    pub fn deleteTextureManually(frameGraph: *RenderAssignerData, registry: *const RenderRegistryData, texPassId: TexPassId, rendererQueue: *RendererQueue) void {
        deleteTextureManuel(frameGraph, registry, texPassId, rendererQueue);
    }

    pub fn createBufferManually(frameGraph: *RenderAssignerData, registry: *const RenderRegistryData, bufPassId: BufPassId, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        try createBufferManuel(frameGraph, registry, bufPassId, rendererQueue, memoryMan);
    }

    pub fn deleteBufferManually(frameGraph: *RenderAssignerData, registry: *const RenderRegistryData, bufPassId: BufPassId, rendererQueue: *RendererQueue) void {
        deleteBufferManuel(frameGraph, registry, bufPassId, rendererQueue);
    }

    fn getBufHardwareId(frameGraph: *const RenderAssignerData, registry: *const RenderRegistryData, name: []const u8) !BufId {
        const bufPassId = try registry.getBufferPassId(name);
        const hardwareBufId = frameGraph.bufAssigns.getByKey(bufPassId);
        return hardwareBufId;
    }

    fn getTexHardwareId(frameGraph: *const RenderAssignerData, registry: *const RenderRegistryData, name: []const u8) !TexId {
        const texPassId = try registry.getTexturePassId(name);
        const hardwareTexId = frameGraph.texAssigns.getByKey(texPassId);
        return hardwareTexId;
    }

    pub fn fillUiHardwareIds(frameGraph: *const RenderAssignerData, registry: *const RenderRegistryData, uiData: *UiData) !void { // UiData not const!!!!!!!!!!!
        for (uiData.uiNodes.slice()) |*uiNode| {
            if (uiNode.imguiVB != .bufName) return error.UiImguiVBNeedsToBeNameForResolve;
            if (uiNode.imguiIB != .bufName) return error.UiImguiIBNeedsToBeNameForResolve;

            const imguiVBHardwareID = try getBufHardwareId(frameGraph, registry, uiNode.imguiVB.bufName);
            const imguiIBHardwareID = try getBufHardwareId(frameGraph, registry, uiNode.imguiIB.bufName);

            uiNode.imguiVB = .{ .bufId = imguiVBHardwareID };
            uiNode.imguiIB = .{ .bufId = imguiIBHardwareID };
        }

        for (uiData.uiDraws.slice()) |*uiDraw| {
            if (uiDraw.drawTex != .texName) return error.UiImguiDrawTexNeedsToBeNameForResolve;
            const imguiTexHardwareID = try getTexHardwareId(frameGraph, registry, uiDraw.drawTex.texName);
            uiDraw.drawTex = .{ .texId = imguiTexHardwareID };
        }
    }

    pub fn processQueue(passResource: *const RenderAssignerData, registry: *const RenderRegistryData, assignerQueue: *RenderAssignerQueue, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        const arena = memoryMan.getGlobalArena();

        for (assignerQueue.get()) |event| {
            switch (event) {
                .updateBuffer => |updateBuffer| {
                    var hardwareId: BufId = undefined;

                    switch (updateBuffer.bufUnion) {
                        .bufId => |bufId| hardwareId = bufId,
                        .bufName => |bufName| hardwareId = try getBufHardwareId(passResource, registry, bufName),
                        .bufPassId => |bufPassId| {
                            if (passResource.bufAssigns.isKeyUsed(bufPassId) == false) {
                                std.debug.print("ERROR: RenderAssignerSys Processing Queue Update Buffer Assignment Empty ({s})\n", .{try registry.getBufferName(bufPassId)});
                                return error.ProcessQueueUpdateBufferAssignemntEmpty;
                            }
                            hardwareId = passResource.bufAssigns.getByKey(bufPassId);
                        },
                    }

                    const PayloadPtr = @FieldType(RendererQueue.RendererEvent, "updateBuffer");
                    const Payload = std.meta.Child(PayloadPtr);
                    const updateBufferPtr = try arena.create(Payload);
                    updateBufferPtr.* = .{ .bufId = hardwareId, .data = updateBuffer.data };

                    rendererQueue.append(.{ .updateBuffer = updateBufferPtr });
                    // std.debug.print("FrameGraph: Update Buffer ({}) send to Renderer\n", .{updateBuffer.bufEnum});
                },
                .updateBufferSegment => |updateBufferSegment| {
                    var hardwareId: BufId = undefined;

                    switch (updateBufferSegment.bufUnion) {
                        .bufId => |bufId| hardwareId = bufId,
                        .bufName => |bufName| hardwareId = try getBufHardwareId(passResource, registry, bufName),
                        .bufPassId => |bufPassId| {
                            if (passResource.bufAssigns.isKeyUsed(bufPassId) == false) {
                                std.debug.print("ERROR: RenderAssignerSys Processing Queue Update Buffer Assignment Empty ({s})\n", .{try registry.getBufferName(bufPassId)});
                                return error.ProcessQueueUpdateBufferAssignemntEmpty;
                            }
                            hardwareId = passResource.bufAssigns.getByKey(bufPassId);
                        },
                    }

                    const PayloadPtr = @FieldType(RendererQueue.RendererEvent, "updateBufferSegment");
                    const Payload = std.meta.Child(PayloadPtr);
                    const updateBufferSegmentPtr = try arena.create(Payload);
                    updateBufferSegmentPtr.* = .{ .bufId = hardwareId, .data = updateBufferSegment.data, .elementOffset = updateBufferSegment.elementOffset };

                    rendererQueue.append(.{ .updateBufferSegment = updateBufferSegmentPtr });
                    // std.debug.print("FrameGraph: Update Buffer Segment ({}) send to Renderer\n", .{updateBufferSegment.bufEnum});
                },
                .updateTexture => |updateTexture| {
                    var hardwareId: TexId = undefined;

                    switch (updateTexture.texUnion) {
                        .texId => |texId| hardwareId = texId,
                        .texName => |texName| hardwareId = try getTexHardwareId(passResource, registry, texName),
                        .texPassId => |texPassId| {
                            if (passResource.texAssigns.isKeyUsed(texPassId) == false) {
                                std.debug.print("ERROR: RenderAssignerSys Processing Queue Update Texture Assignment Empty ({s})\n", .{try registry.getTextureName(texPassId)});
                                return error.ProcessQueueUpdateTextureAssignemntEmpty;
                            }
                            hardwareId = passResource.texAssigns.getByKey(texPassId);
                        },
                    }

                    const PayloadPtr = @FieldType(RendererQueue.RendererEvent, "updateTexture");
                    const Payload = std.meta.Child(PayloadPtr);
                    const updateTexturePtr = try arena.create(Payload);
                    updateTexturePtr.* = .{ .texId = hardwareId, .data = updateTexture.data, .newExtent = updateTexture.newExtent };

                    rendererQueue.append(.{ .updateTexture = updateTexturePtr });
                    // std.debug.print("FrameGraph: Update Texture ({}) send to Renderer\n", .{updateTexture.texEnum});
                },
            }
        }
        assignerQueue.clear();
    }
};

fn bufDescEqual(bufDesc1: *const BufDesc, bufDesc2: *const BufDesc) bool {
    return std.meta.eql(bufDesc1.*, bufDesc2.*);
}

fn texDescEqual(texDesc1: *const TexDesc, texDesc2: *const TexDesc) bool {
    return std.meta.eql(texDesc1.*, texDesc2.*);
}
