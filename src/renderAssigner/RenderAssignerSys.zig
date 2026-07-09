const UiData = @import("../ui/UiData.zig").UiData;

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

const texToRes = @import("../renderGraph/components.zig").texToRes;
const bufToRes = @import("../renderGraph/components.zig").bufToRes;
const resToBuf = @import("../renderGraph/components.zig").resToBuf;
const resToTex = @import("../renderGraph/components.zig").resToTex;

const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const RenderAssignerData = @import("../renderAssigner/RenderAssignerData.zig").RenderAssignerData;
const RenderAssignerQueue = @import("../renderAssigner/RenderAssignerQueue.zig").RenderAssignerQueue;
const RenderGraphData = @import("../renderGraph/RenderGraphData.zig").RenderGraphData;

pub const RenderAssignerSys = struct {
    pub fn assign(self: *RenderAssignerData, renderGraph: *const RenderGraphData, registry: *const RenderRegistryData, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        // Resets
        self.bufAssigns.clear();
        self.texAssigns.clear();

        try assignManuel(self, renderGraph, registry, rendererQueue, memoryMan);
        try assignTransients(self, renderGraph, registry, rendererQueue, memoryMan);

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

    pub fn assignManuel(self: *RenderAssignerData, _: *const RenderGraphData, _: *const RenderRegistryData, _: *RendererQueue, _: *MemoryManager) !void {
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
    }

    pub fn assignTransients(self: *RenderAssignerData, renderGraph: *const RenderGraphData, registry: *const RenderRegistryData, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        const mapper = &renderGraph.mapper;
        const groups = &renderGraph.group;

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
                rendererQueue.append(.{ .removeBuffer = transientBuf.hardwareBuf }); // (Stop Renderer missing?)
                std.debug.print("6.Resource Assigner: Transient Buf (BufId {}) Deletion send to Renderer\n", .{transientBuf.hardwareBuf});

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
                rendererQueue.append(.{ .removeTexture = transientTex.hardwareTex }); // (Stop Renderer missing?)
                std.debug.print("6.Resource Assigner: Transient Tex (TexId {}) Deletion send to Renderer\n", .{transientTex.hardwareTex});

                freeUpTexId(self, transientTex.hardwareTex);
                self.unusedTransientTexes.swapRemove(@intCast(index));
            } else {
                transientTex.unusedCounter += 1;
            }
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
