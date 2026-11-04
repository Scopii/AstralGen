const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const RenderAssignerData = @import("../renderAssigner/RenderAssignerData.zig").RenderAssignerData;
const RenderAssignerQueue = @import("../renderAssigner/RenderAssignerQueue.zig").RenderAssignerQueue;
const RenderGraphData = @import("../renderGraph/RenderGraphData.zig").RenderGraphData;
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
const UiData = @import("../ui/UiData.zig").UiData;
const std = @import("std");
const TexInf = TextureMeta.TexInf;
const BufInf = BufferMeta.BufInf;
const MANUAL_STORAGE_COUNT = @import("../renderAssigner/RenderAssignerData.zig").MANUAL_STORAGE_COUNT;

pub const RenderAssignerSys = struct {
    pub fn assign(
        self: *RenderAssignerData,
        renderGraph: *const RenderGraphData,
        registry: *const RenderRegistryData,
        assignerQueue: *RenderAssignerQueue,
        rendererQueue: *RendererQueue,
        memoryMan: *MemoryManager,
    ) !void {
        // Mark SubResource Updates
        self.requests.clear();
        // Resets
        self.bufAssigns.clear();
        self.texAssigns.clear();

        self.manualTexRotated.clear();
        self.manualBufRotated.clear();

        try processUpdateQueue(self, registry, assignerQueue, rendererQueue, memoryMan);

        try assignManuel(self, registry);

        try assignTransients(self, renderGraph, registry, rendererQueue, memoryMan);

        // Debug
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("6.ResourceAssigner (Assigned Frame: {})\n", .{self.assignedFrames});
            for (self.usedTransientBufs.constSlice(), 0..) |buf, i| {
                std.debug.print(" - Transient Buf {} -> Buf (BufId {}) (in use for {} Builds)\n", .{ i, buf.hardwareBuf.val(), buf.inUseCounter });
            }
            for (self.usedTransientTexes.constSlice(), 0..) |tex, i| {
                std.debug.print(" - Transient Tex {} -> Tex (TexId {}) (in use for {} Builds)\n", .{ i, tex.hardwareTex.val(), tex.inUseCounter });
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

        self.assignedFrames += 1;
    }

    pub fn assignManuel(self: *RenderAssignerData, registry: *const RenderRegistryData) !void {
        for (self.manualTexCycle.getItems(), 0..) |*storageIndex, i| {
            const texPassId = self.manualTexCycle.getKeyByIndex(@intCast(i));

            const texInf = try registry.getTextureDefinition(texPassId);
            const realIndex = switch (texInf.update) {
                .Rarely => storageIndex.*,
                .Often => storageIndex.*,
                .PerFrame => self.assignedFrames % MANUAL_STORAGE_COUNT,
            };

            storageIndex.* = @intCast(realIndex);

            const manualStorage = &self.manualStorages[realIndex];
            const texId = manualStorage.manualTexes.getByKey(texPassId).id;

            self.texAssigns.upsert(texPassId, texId);
        }

        for (self.manualBufCycle.getItems(), 0..) |*storageIndex, i| {
            const bufPassId = self.manualBufCycle.getKeyByIndex(@intCast(i));

            const bufInf = try registry.getBufferDefinition(bufPassId);
            const realIndex = switch (bufInf.update) {
                .Rarely => storageIndex.*,
                .Often => storageIndex.*,
                .PerFrame => self.assignedFrames % MANUAL_STORAGE_COUNT,
            };

            storageIndex.* = @intCast(realIndex);

            const manualStorage = &self.manualStorages[realIndex];
            const bufId = manualStorage.manualBufs.getByKey(bufPassId).id;

            self.bufAssigns.upsert(bufPassId, bufId);
        }
    }

    pub fn assignTransients(
        self: *RenderAssignerData,
        renderGraph: *const RenderGraphData,
        registry: *const RenderRegistryData,
        rendererQueue: *RendererQueue,
        memoryMan: *MemoryManager,
    ) !void {
        const share = &renderGraph.share;

        self.unusedTransientBufs.appendSliceAssumeCapacity(self.usedTransientBufs.constSlice());
        self.unusedTransientTexes.appendSliceAssumeCapacity(self.usedTransientTexes.constSlice());

        self.usedTransientBufs.clear();
        self.usedTransientTexes.clear();

        // Buffer Pooling
        for (share.sharedBuffers.constSlice()) |sharedBufLifetime| {
            const bufDesc = sharedBufLifetime.bufDesc;
            var candidateIndex: ?u16 = null;

            for (self.unusedTransientBufs.constSlice(), 0..) |transientBuf, i| {
                // Continue if resource is still in use!
                if (transientBuf.inUseCounter > 0) continue;

                if (bufDescEqual(&transientBuf.bufDesc, &bufDesc)) {
                    candidateIndex = @intCast(i);
                    break;
                }
            }

            const inUseCounter: i8 = switch (bufDesc.update) {
                .PerFrame => 0,
                .Often, .Rarely => 0,
            };

            if (candidateIndex) |index| {
                var candidate = self.unusedTransientBufs.swapRemoveReturn(index);
                candidate.inUseCounter = inUseCounter;
                self.usedTransientBufs.append(candidate) catch {
                    std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientBufs\n", .{});
                    return error.CouldNotAppend;
                };
            } else {
                const candidate = TransientBuffer{ .bufDesc = bufDesc, .hardwareBuf = try getFreeBufId(self), .inUseCounter = inUseCounter };
                try createTransientBuffer(self, bufDesc, candidate.hardwareBuf, rendererQueue, memoryMan);
                self.usedTransientBufs.append(candidate) catch {
                    std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientBufs\n", .{});
                    return error.CouldNotAppend;
                };
            }
        }

        // Texture Pooling
        for (share.sharedTextures.constSlice()) |sharedTexLifetime| {
            const texDesc = sharedTexLifetime.texDesc;

            var exactMatch: ?u16 = null;
            var compatibleMatch: ?u16 = null;

            for (self.unusedTransientTexes.constSlice(), 0..) |transientTex, i| {
                // Continue if resource is still in use!
                if (transientTex.inUseCounter > 0) continue;

                // Try searching exact match first
                if (std.meta.eql(transientTex.texDesc, texDesc) == true) {
                    exactMatch = @intCast(i);
                    break;
                }
                // Try searching superset
                if (texDescCompatibale(&transientTex.texDesc, &texDesc)) {
                    compatibleMatch = @intCast(i);
                }
            }

            const candidateIndex = exactMatch orelse compatibleMatch orelse null;

            const inUseCounter: i8 = switch (texDesc.update) {
                .PerFrame => 0,
                .Often, .Rarely => 0,
            };

            if (candidateIndex) |index| {
                var candidate = self.unusedTransientTexes.swapRemoveReturn(index);
                candidate.inUseCounter = inUseCounter;
                self.usedTransientTexes.append(candidate) catch {
                    std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientTexes\n", .{});
                    return error.CouldNotAppend;
                };
            } else {
                const candidate = TransientTexture{ .texDesc = texDesc, .hardwareTex = try getFreeTexId(self), .inUseCounter = inUseCounter };
                try createTransientTexture(self, texDesc, candidate.hardwareTex, rendererQueue, memoryMan);
                self.usedTransientTexes.append(candidate) catch {
                    std.debug.print("ERROR: 6.ResourceAssigner: Could not Append to usedTransientTexes\n", .{});
                    return error.CouldNotAppend;
                };
            }
        }

        // NEW Assignments
        for (share.bufShareIndices.getConstItems(), 0..) |sharedIndex, index| {
            const bufPassId = share.bufShareIndices.getKeyByIndex(@intCast(index));

            if (self.bufAssigns.isKeyUsed(bufPassId) == true) {
                const bufName = try registry.getBufferName(bufPassId);
                std.debug.print("ERROR: 6.ResourceAssigner: Buffer Name {s} already assigned!\n", .{bufName});
                return error.BufEnumAlreadyAssigned;
            }
            const bufHardwareId = self.usedTransientBufs.buffer[sharedIndex].hardwareBuf;
            self.bufAssigns.upsert(bufPassId, bufHardwareId);
        }

        for (share.texShareIndices.getConstItems(), 0..) |sharedIndex, index| {
            const texPassId = share.texShareIndices.getKeyByIndex(@intCast(index));

            const texHardwareId = self.usedTransientTexes.buffer[sharedIndex].hardwareTex;

            if (self.texAssigns.isKeyUsed(texPassId)) {
                const texName = try registry.getTextureName(texPassId);
                std.debug.print("ERROR: 6.ResourceAssigner: Texture Name {s} already assigned!\n", .{texName});
                return error.TexEnumAlreadyAssigned;
            }
            self.texAssigns.upsert(texPassId, texHardwareId);
        }

        // Cleanup Buffers
        const unusedBufsLen = self.unusedTransientBufs.len;
        for (0..unusedBufsLen) |i| {
            const index = unusedBufsLen - 1 - i;
            const transientBuf = &self.unusedTransientBufs.buffer[index];

            if (transientBuf.inUseCounter + rc.FRAME_BUILDS_TILL_TRANSIENT_DELETION <= 0) {
                rendererQueue.append(.{ .removeBuffer = transientBuf.hardwareBuf }); // (Stop Renderer missing?)

                self.requests.append(.{ .destroyBuf = transientBuf.hardwareBuf }) catch return error.RenderAssignerRequestsFull;
                std.debug.print("6.Resource Assigner: Transient Buf (BufId {}) Deletion send to Renderer\n", .{transientBuf.hardwareBuf});

                freeUpBufId(self, transientBuf.hardwareBuf);
                self.unusedTransientBufs.swapRemove(@intCast(index));
            } else {
                transientBuf.inUseCounter -= 1;
            }
        }

        // Cleanup Textures
        const unusedTexesLen = self.unusedTransientTexes.len;
        for (0..unusedTexesLen) |i| {
            const index = unusedTexesLen - 1 - i;
            const transientTex = &self.unusedTransientTexes.buffer[index];

            if (transientTex.inUseCounter + rc.FRAME_BUILDS_TILL_TRANSIENT_DELETION <= 0) {
                rendererQueue.append(.{ .removeTexture = transientTex.hardwareTex }); // (Stop Renderer missing?)

                self.requests.append(.{ .destroyTex = transientTex.hardwareTex }) catch return error.RenderAssignerRequestsFull;
                std.debug.print("6.Resource Assigner: Transient Tex (TexId {}) Deletion send to Renderer\n", .{transientTex.hardwareTex});

                freeUpTexId(self, transientTex.hardwareTex);
                self.unusedTransientTexes.swapRemove(@intCast(index));
            } else {
                transientTex.inUseCounter -= 1;
            }
        }
    }

    fn createTransientBuffer(self: *RenderAssignerData, bufDesc: BufDesc, bufId: BufId, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
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

        self.requests.append(.{ .createBuf = bufId }) catch return error.RenderAssignerRequestsFull;
        std.debug.print("6.Resource Assigner: Transient Buf (BufId {}) Creation send to Renderer\n", .{bufInf.id});
    }

    fn createTransientTexture(self: *RenderAssignerData, texDesc: TexDesc, texId: TexId, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
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

        self.requests.append(.{ .createTex = texId }) catch return error.RenderAssignerRequestsFull;
        std.debug.print("6.Resource Assigner: Transient Tex (TexId {}) Creation send to Renderer\n", .{texInf.id});
    }

    fn createBufferManuel(self: *RenderAssignerData, registry: *const RenderRegistryData, rootBufName: []const u8, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        const rootBuf = registry.getBufferPassId(rootBufName) catch return error.createBufferManuelNoBufPassId;
        const bufDesc = try registry.getBufferDefinition(rootBuf);

        const subresCount = switch (bufDesc.update) {
            .Rarely => 1,
            .Often => MANUAL_STORAGE_COUNT,
            .PerFrame => MANUAL_STORAGE_COUNT,
        };

        for (0..subresCount) |i| {
            const manualStorage = &self.manualStorages[i];

            switch (bufDesc.share) {
                .transient => return error.ManualTextureCantBeTransient,
                else => {},
            }
            // if (bufDesc.fitPass == true) return error.ManualBufferCantResize;

            const bufId = try getFreeBufId(self);

            const bufInf = BufInf{
                .id = bufId,
                .mem = bufDesc.mem,
                .elementSize = bufDesc.elementSize,
                .len = bufDesc.len,
                .typ = bufDesc.typ,
                .update = bufDesc.update,
                .resize = bufDesc.resize,
            };

            manualStorage.manualBufs.upsert(rootBuf, bufInf);

            // RENDERER QUEUE SEND CREATE (AND UPDATE!) (Stop Renderer?)
            const arena = memoryMan.getGlobalArena();
            const AddBufPtr = @FieldType(RendererQueue.RendererEvent, "addBuffer");
            const AddBuf = std.meta.Child(AddBufPtr);
            const bufferPtr = try arena.create(AddBuf);
            bufferPtr.* = .{ .bufInf = bufInf, .data = null };
            rendererQueue.append(.{ .addBuffer = bufferPtr });

            self.requests.append(.{ .createBuf = bufId }) catch return error.RenderAssignerRequestsFull;
            std.debug.print("6.Resource Assigner: Root Buf {s} (BufId {}) Creation send to Renderer\n", .{ rootBufName, bufId });
        }

        self.manualBufCycle.upsert(rootBuf, subresCount - 1);
    }

    fn deleteBufferManuel(self: *RenderAssignerData, registry: *const RenderRegistryData, rootBufName: []const u8, rendererQueue: *RendererQueue) !void {
        const rootBufKey = registry.getBufferPassId(rootBufName) catch return error.deleteBufferManualNoBufPassId;
        if (self.manualBufCycle.isKeyUsed(rootBufKey) == false) return error.DeleteBufferNotManual;

        for (&self.manualStorages) |*manualStorage| {
            const isUsed = manualStorage.manualBufs.isKeyUsed(rootBufKey);
            if (isUsed == false) continue;

            const bufId = manualStorage.manualBufs.getByKey(rootBufKey).id;
            freeUpBufId(self, bufId);
            manualStorage.manualBufs.remove(rootBufKey);
            rendererQueue.append(.{ .removeBuffer = bufId }); // (Stop Renderer missing?)

            self.requests.append(.{ .destroyBuf = bufId }) catch return error.RenderAssignerRequestsFull;
            std.debug.print("6.Resource Assigner: Root Buf {s} (BufId {}) Deletion send to Renderer\n", .{ rootBufName, bufId.val() });
        }

        self.manualBufCycle.remove(rootBufKey);
    }

    fn createTextureManuel(self: *RenderAssignerData, registry: *const RenderRegistryData, rootTexName: []const u8, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        const rootTex = registry.getTexturePassId(rootTexName) catch return error.createBufferManuelNoBufPassId;
        const texDesc = try registry.getTextureDefinition(rootTex);

        const subresCount = switch (texDesc.update) {
            .Rarely => 1,
            .Often => MANUAL_STORAGE_COUNT,
            .PerFrame => MANUAL_STORAGE_COUNT,
        };

        for (0..subresCount) |i| {
            const manualStorage = &self.manualStorages[i];

            switch (texDesc.share) {
                .transient => return error.ManualTextureCantBeTransient,
                else => {},
            }
            if (texDesc.fitPass) return error.ManualTextureCantFitPass;

            const texId = try getFreeTexId(self);

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

            manualStorage.manualTexes.upsert(rootTex, texInf);

            // RENDERER QUEUE SEND CREATE (AND UPDATE!) (Stop Renderer?)
            const arena = memoryMan.getGlobalArena();
            const AddTexPtr = @FieldType(RendererQueue.RendererEvent, "addTexture");
            const AddTex = std.meta.Child(AddTexPtr);
            const addTextureDataPtr = try arena.create(AddTex);
            addTextureDataPtr.* = .{ .texInf = texInf, .data = null };
            rendererQueue.append(.{ .addTexture = addTextureDataPtr });

            self.requests.append(.{ .createTex = texId }) catch return error.RenderAssignerRequestsFull;
            std.debug.print("6.Resource Assigner: Root Tex {s} (TexId {}) Creation send to Renderer\n", .{ rootTexName, texId });
        }

        self.manualTexCycle.upsert(rootTex, subresCount - 1);
    }

    fn deleteTextureManuel(self: *RenderAssignerData, registry: *const RenderRegistryData, rootTexName: []const u8, rendererQueue: *RendererQueue) !void {
        const rootTexId = registry.getTexturePassId(rootTexName) catch return error.deleteTextureManualNoTexPassId;
        if (self.manualTexCycle.isKeyUsed(rootTexId) == false) return error.DeleteBufferNotManual;

        for (&self.manualStorages) |*manualStorage| {
            const isUsed = manualStorage.manualTexes.isKeyUsed(rootTexId);
            if (isUsed == false) continue;

            const texInf = manualStorage.manualTexes.getByKey(rootTexId);
            freeUpTexId(self, texInf.id);
            manualStorage.manualTexes.remove(rootTexId);
            rendererQueue.append(.{ .removeTexture = texInf.id }); // (Stop Renderer missing?)

            self.requests.append(.{ .destroyTex = texInf.id }) catch return error.RenderAssignerRequestsFull;
            std.debug.print("6.Resource Assigner: Root Tex {s} (TexId {}) Deletion send to Renderer\n", .{ rootTexName, texInf.id.val() });
        }

        self.manualTexCycle.remove(rootTexId);
    }

    fn getFreeBufId(assignerData: *RenderAssignerData) !BufId {
        const bufKey = assignerData.bufIdPool.tryReserveKey() orelse return error.BufIdsFullyUsed;
        return .id(bufKey);
    }

    fn freeUpBufId(assignerData: *RenderAssignerData, bufId: BufId) void {
        assignerData.bufIdPool.freeKey(bufId.val());
    }

    fn getFreeTexId(assignerData: *RenderAssignerData) !TexId {
        const texKey = assignerData.texIdPool.tryReserveKey() orelse return error.TexIdsFullyUsed;
        return .id(texKey);
    }

    fn freeUpTexId(assignerData: *RenderAssignerData, texId: TexId) void {
        assignerData.texIdPool.freeKey(texId.val());
    }

    fn processUpdateQueue(self: *RenderAssignerData, registry: *const RenderRegistryData, assignerQueue: *RenderAssignerQueue, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        const arena = memoryMan.getGlobalArena();

        for (assignerQueue.get()) |event| {
            switch (event) {
                .createManualBuffer => |bufName| try createBufferManuel(self, registry, bufName, rendererQueue, memoryMan),
                .deleteManualBuffer => |bufName| try deleteBufferManuel(self, registry, bufName, rendererQueue),
                .createManualTexture => |texName| try createTextureManuel(self, registry, texName, rendererQueue, memoryMan),
                .deleteManualTexture => |texName| try deleteTextureManuel(self, registry, texName, rendererQueue),

                .updateBuffer => |updateBuffer| {
                    const bufPassId = try registry.getBufferPassId(updateBuffer.bufName);

                    // increment manual Subresource Index
                    if (self.manualBufCycle.isKeyUsed(bufPassId) == false) return error.BufferUpdateCantFindManualBufCycle;
                    const bufCycle = self.manualBufCycle.getPtrByKey(bufPassId);

                    const bufDesc = try registry.getBufferDefinition(bufPassId);
                    if (self.manualBufRotated.isKeyUsed(bufPassId) == false) {
                        switch (bufDesc.update) {
                            .PerFrame => bufCycle.* = @intCast(self.assignedFrames % MANUAL_STORAGE_COUNT),
                            .Often => bufCycle.* = (bufCycle.* + 1) % MANUAL_STORAGE_COUNT,
                            .Rarely => {
                                const bufName = try registry.getBufferName(bufPassId);
                                try deleteBufferManuel(self, registry, bufName, rendererQueue);
                                try createBufferManuel(self, registry, bufName, rendererQueue, memoryMan);
                            },
                        }
                        self.manualBufRotated.insert(bufPassId, true);
                    } else std.debug.print("WARNING TRIED UPDATING BUFFER MULTIPLE TIMES! ({s})\n", .{try registry.getBufferName(bufPassId)});

                    const updatedCycle = self.manualBufCycle.getByKey(bufPassId); // CHANGED: re-read, delete/create may have moved entries
                    const hardwareId: BufId = self.manualStorages[updatedCycle].manualBufs.getByKey(bufPassId).id;

                    const PayloadPtr = @FieldType(RendererQueue.RendererEvent, "updateBuffer");
                    const Payload = std.meta.Child(PayloadPtr);
                    const updateBufferPtr = try arena.create(Payload);
                    updateBufferPtr.* = .{ .bufId = hardwareId, .data = updateBuffer.data };

                    rendererQueue.append(.{ .updateBuffer = updateBufferPtr });
                    self.requests.append(.{ .updateBuf = hardwareId }) catch return error.RenderAssignerRequestsFull;
                    // std.debug.print("FrameGraph: Update Buffer ({}) send to Renderer\n", .{updateBuffer.bufEnum});
                },
                .updateBufferSegment => |_| {
                    return error.UpdateBufferSegmentIncorrectlyImplemented;
                },
                .updateTexture => |updateTexture| {
                    const texPassId = try registry.getTexturePassId(updateTexture.texName);
                    const texDesc = try registry.getTextureDefinition(texPassId);

                    // increment manual Subresource Index
                    if (self.manualTexCycle.isKeyUsed(texPassId) == false) return error.TextureUpdateCantFindManualBufCycle;
                    const texCycle = self.manualTexCycle.getPtrByKey(texPassId);

                    if (self.manualTexRotated.isKeyUsed(texPassId) == false) {
                        switch (texDesc.update) {
                            .PerFrame => texCycle.* = @intCast(self.assignedFrames % MANUAL_STORAGE_COUNT),
                            .Often => texCycle.* = (texCycle.* + 1) % MANUAL_STORAGE_COUNT,
                            .Rarely => {
                                const texName = try registry.getTextureName(texPassId);
                                try deleteTextureManuel(self, registry, texName, rendererQueue);
                                try createTextureManuel(self, registry, texName, rendererQueue, memoryMan);
                            },
                        }

                        self.manualTexRotated.insert(texPassId, true);
                    } else std.debug.print("WARNING TRIED UPDATING TEXTURE MULTIPLE TIMES! ({s})\n", .{try registry.getTextureName(texPassId)});

                    const newCycle = self.manualTexCycle.getByKey(texPassId);
                    const hardwareId: TexId = self.manualStorages[newCycle].manualTexes.getByKey(texPassId).id;

                    const PayloadPtr = @FieldType(RendererQueue.RendererEvent, "updateTexture");
                    const Payload = std.meta.Child(PayloadPtr);
                    const updateTexturePtr = try arena.create(Payload);
                    updateTexturePtr.* = .{ .texId = hardwareId, .data = updateTexture.data, .newExtent = updateTexture.newExtent };

                    rendererQueue.append(.{ .updateTexture = updateTexturePtr });
                    self.requests.append(.{ .updateTex = hardwareId }) catch return error.RenderAssignerRequestsFull;
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

// fn texDescComptabile(texDesc1: *const TexDesc, texDesc2: *const TexDesc) bool {
//     return std.meta.eql(texDesc1.*, texDesc2.*);
// }

fn texDescCompatibale(texDesc1: *const TexDesc, texDesc2: *const TexDesc) bool {
    const compatibleShare = texDesc1.share == texDesc2.share;
    const compatibleMem = texDesc1.mem == texDesc2.mem;
    const compatibleTyp = texDesc1.typ == texDesc2.typ;
    const compatibleWidth = texDesc1.width == texDesc2.width;
    const compatibleHeight = texDesc1.height == texDesc2.height;
    const compatibleDepth = texDesc1.depth == texDesc2.depth;
    const compatibleUpdate = texDesc1.update == texDesc2.update;
    const compatibleResize = texDesc1.resize == .Block and texDesc2.resize == .Block;

    const compatibleDescriptor = texDesc1.descriptors == texDesc2.descriptors or
        texDesc1.descriptors == .StorageSampled or
        texDesc2.descriptors == .None; // Needing no descriptor fits any pooled texture

    const usageEqual = // non aggressive share with no extra flags
        texDesc1.texUse.colorAtt == texDesc2.texUse.colorAtt and
        texDesc1.texUse.depthAtt == texDesc2.texUse.depthAtt and
        texDesc1.texUse.storage == texDesc2.texUse.storage and
        texDesc1.texUse.sampled == texDesc2.texUse.sampled and
        texDesc1.texUse.transferSrc == texDesc2.texUse.transferSrc and
        texDesc1.texUse.transferDst == texDesc2.texUse.transferDst;

    const usageCovers = // pooled texture has every usage the needed one has
        (!texDesc2.texUse.colorAtt or texDesc1.texUse.colorAtt) and
        (!texDesc2.texUse.depthAtt or texDesc1.texUse.depthAtt) and
        (!texDesc2.texUse.storage or texDesc1.texUse.storage) and
        (!texDesc2.texUse.sampled or texDesc1.texUse.sampled) and
        (!texDesc2.texUse.transferSrc or texDesc1.texUse.transferSrc) and
        (!texDesc2.texUse.transferDst or texDesc1.texUse.transferDst);

    const compatibleUsage = if (rc.FRAME_GRAPH_AGGRESSIVE_TEXTURE_SHARE) usageCovers else usageEqual;

    return compatibleShare and
        compatibleMem and
        compatibleTyp and
        compatibleWidth and
        compatibleHeight and
        compatibleDepth and
        compatibleUpdate and
        compatibleResize and
        compatibleDescriptor and
        compatibleUsage;
}
