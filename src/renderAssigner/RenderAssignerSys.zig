const RenderAssignerQueue = @import("../renderAssigner/RenderAssignerQueue.zig").RenderAssignerQueue;
const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const RenderAssignerData = @import("../renderAssigner/RenderAssignerData.zig").RenderAssignerData;
const RenderGraphData = @import("../renderGraph/RenderGraphData.zig").RenderGraphData;
const TransientTexture = @import("../renderGraph/components.zig").TransientTexture;
const TransientBuffer = @import("../renderGraph/components.zig").TransientBuffer;
const SubResTexture = @import("../renderGraph/components.zig").SubResTexture;
const SubResBuffer = @import("../renderGraph/components.zig").SubResBuffer;
const RendererQueue = @import("../render/RendererQueue.zig").RendererQueue;
const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;
const ManualBuf = @import("../renderGraph/components.zig").ManualBuf;
const ManualTex = @import("../renderGraph/components.zig").ManualTex;
const TexDesc = @import("../render/types/res/Texture.zig").TexDesc;
const BufDesc = @import("../render/types/res/Buffer.zig").BufDesc;
const TexInf = @import("../render/types/res/Texture.zig").TexInf;
const BufInf = @import("../render/types/res/Buffer.zig").BufInf;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const TexId = @import("../.configs/idConfig.zig").TexId;
const BufId = @import("../.configs/idConfig.zig").BufId;
const rc = @import("../.configs/renderConfig.zig");
const UiData = @import("../ui/UiData.zig").UiData;
const vhE = @import("../render/help/Enums.zig");
const vk = @import("../.modules/vk.zig").c;
const std = @import("std");

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

        self.bufUpdates.clear();
        self.texUpdates.clear();

        try destroyManual(self, rendererQueue);

        try processQueue(self, registry, assignerQueue, rendererQueue, memoryMan);

        try processUpdateQueue(self, registry, assignerQueue, rendererQueue, memoryMan);

        try assignManuel(self, registry, rendererQueue);

        try sendUpdates(self, rendererQueue);

        try assignTransients(self, renderGraph, registry, rendererQueue, memoryMan);

        assignerQueue.clear();

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

    pub fn destroyManual(self: *RenderAssignerData, rendererQueue: *RendererQueue) !void {
        const subBufDeletions = self.subBufDeletions.constSlice();
        for (0..subBufDeletions.len) |i| {
            const realIndex: u32 = @intCast(subBufDeletions.len - i - 1);
            const bufDest = subBufDeletions[realIndex];

            if (self.assignedFrames >= bufDest.deletionFrame) {
                self.subBufDeletions.swapRemove(realIndex);

                const bufId = bufDest.subBuf;
                freeUpBufId(self, bufId);
                try rendererQueue.append(.{ .removeBuffer = bufId }); // (Stop Renderer missing?)
                self.requests.append(.{ .destroyBuf = bufId }) catch return error.RenderAssignerRequestsFull;
            }
        }

        const subTexDeletions = self.subTexDeletions.constSlice();
        for (0..subTexDeletions.len) |i| {
            const realIndex: u32 = @intCast(subTexDeletions.len - i - 1);
            const texDest = subTexDeletions[realIndex];

            if (self.assignedFrames >= texDest.deletionFrame) {
                self.subTexDeletions.swapRemove(realIndex);
                const texId = texDest.subTex;
                freeUpTexId(self, texId);
                try rendererQueue.append(.{ .removeTexture = texId }); // (Stop Renderer missing?)
                self.requests.append(.{ .destroyTex = texId }) catch return error.RenderAssignerRequestsFull;
            }
        }
    }

    pub fn assignManuel(self: *RenderAssignerData, registry: *const RenderRegistryData, rendererQueue: *RendererQueue) !void {
        for (self.manualBufs.getItems(), 0..) |*manualBuf, i| {
            const bufPassId = self.manualBufs.getKeyByIndex(@intCast(i));
            const bufDesc = try registry.getBufferDefinition(bufPassId);

            if (manualBuf.updateTyp != bufDesc.update) return error.ResourceUpdateTypHasToMatch;

            // Rotate Subresource and use new
            switch (manualBuf.updateTyp) {
                .Rarely => {
                    // Already handled by newly created Resource
                },
                .Often => {
                    // Cycle if Update Exists
                    if (self.bufUpdates.isKeyUsed(bufPassId) == true) {
                        const subId = manualBuf.subBufs.removeFirstItem() orelse return error.SubResMissing;
                        try manualBuf.subBufs.appendLast(subId);
                    }
                },
                .PerFrame => {
                    // Always Cycle
                    const subId = manualBuf.subBufs.removeFirstItem() orelse return error.SubResMissing;
                    try manualBuf.subBufs.appendLast(subId);
                },
            }

            const subId = manualBuf.subBufs.getFirstItem() orelse return error.SubResMissing;

            // Create Subresource if needed
            try ensureSubBuf(self, bufPassId, subId, bufDesc, rendererQueue);

            self.manualSubBufs.getPtrByKey(subId).lastUsedFrame = self.assignedFrames;

            self.bufAssigns.upsert(bufPassId, subId);
        }

        for (self.manualTexes.getItems(), 0..) |*manualTex, i| {
            const texPassId = self.manualTexes.getKeyByIndex(@intCast(i));
            const texDesc = try registry.getTextureDefinition(texPassId);

            if (manualTex.updateTyp != texDesc.update) return error.ResourceUpdateTypHasToMatch;

            // Rotate Subresource and use new
            switch (manualTex.updateTyp) {
                .Rarely => {
                    // Already handled by newly created Resource
                },
                .Often => {
                    // Cycle if Update Exists
                    if (self.texUpdates.isKeyUsed(texPassId) == true) {
                        const subId = manualTex.subTexes.removeFirstItem() orelse return error.SubResMissing;
                        try manualTex.subTexes.appendLast(subId);
                    }
                },
                .PerFrame => {
                    // Always Cycle
                    const subId = manualTex.subTexes.removeFirstItem() orelse return error.SubResMissing;
                    try manualTex.subTexes.appendLast(subId);
                },
            }

            const subId = manualTex.subTexes.getFirstItem() orelse return error.SubResMissing;

            // Create Subresource if needed
            try ensureSubTex(self, texPassId, subId, texDesc, rendererQueue);

            self.manualSubTexes.getPtrByKey(subId).lastUsedFrame = self.assignedFrames;

            self.texAssigns.upsert(texPassId, subId);
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

        // Transient Buffer Pooling
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

        // Transient Texture Pooling
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

        // Buffer Assignments
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

        // Texture Assignments
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

        // Cleanup Transient Buffers
        const unusedBufsLen = self.unusedTransientBufs.len;
        for (0..unusedBufsLen) |i| {
            const index = unusedBufsLen - 1 - i;
            const transientBuf = &self.unusedTransientBufs.buffer[index];

            if (transientBuf.inUseCounter + rc.FRAME_BUILDS_TILL_TRANSIENT_DELETION <= 0) {
                try rendererQueue.append(.{ .removeBuffer = transientBuf.hardwareBuf }); // (Stop Renderer missing?)

                self.requests.append(.{ .destroyBuf = transientBuf.hardwareBuf }) catch return error.RenderAssignerRequestsFull;
                std.debug.print("6.Resource Assigner: Transient Buf (BufId {}) Deletion send to Renderer\n", .{transientBuf.hardwareBuf});

                freeUpBufId(self, transientBuf.hardwareBuf);
                self.unusedTransientBufs.swapRemove(@intCast(index));
            } else {
                transientBuf.inUseCounter -= 1;
            }
        }

        // Cleanup Transient Textures
        const unusedTexesLen = self.unusedTransientTexes.len;
        for (0..unusedTexesLen) |i| {
            const index = unusedTexesLen - 1 - i;
            const transientTex = &self.unusedTransientTexes.buffer[index];

            if (transientTex.inUseCounter + rc.FRAME_BUILDS_TILL_TRANSIENT_DELETION <= 0) {
                try rendererQueue.append(.{ .removeTexture = transientTex.hardwareTex }); // (Stop Renderer missing?)

                self.requests.append(.{ .destroyTex = transientTex.hardwareTex }) catch return error.RenderAssignerRequestsFull;
                std.debug.print("6.Resource Assigner: Transient Tex (TexId {}) Deletion send to Renderer\n", .{transientTex.hardwareTex});

                freeUpTexId(self, transientTex.hardwareTex);
                self.unusedTransientTexes.swapRemove(@intCast(index));
            } else {
                transientTex.inUseCounter -= 1;
            }
        }
    }

    fn createTransientBuffer(self: *RenderAssignerData, bufDesc: BufDesc, bufId: BufId, rendererQueue: *RendererQueue, _: *MemoryManager) !void {
        const bufInf = BufInf{
            .id = bufId,
            .elementSize = bufDesc.elementSize,
            .len = bufDesc.len,
            .mem = bufDesc.mem,
            .resize = bufDesc.resize,
            .typ = bufDesc.typ,
            .update = bufDesc.update,
        };
        try rendererQueue.append(.{ .addBuffer = .{ .bufInf = bufInf, .data = null } });

        self.requests.append(.{ .createBuf = bufId }) catch return error.RenderAssignerRequestsFull;
        std.debug.print("6.Resource Assigner: Transient Buf (BufId {}) Creation send to Renderer\n", .{bufInf.id});
    }

    fn createTransientTexture(self: *RenderAssignerData, texDesc: TexDesc, texId: TexId, rendererQueue: *RendererQueue, _: *MemoryManager) !void {
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
        try rendererQueue.append(.{ .addTexture = .{ .texInf = texInf, .data = null } });

        self.requests.append(.{ .createTex = texId }) catch return error.RenderAssignerRequestsFull;
        std.debug.print("6.Resource Assigner: Transient Tex (TexId {}) Creation send to Renderer\n", .{texInf.id});
    }

    fn createBufferManuel(self: *RenderAssignerData, registry: *const RenderRegistryData, rootBufName: []const u8, _: *RendererQueue, _: *MemoryManager) !void {
        const bufPassId = registry.getBufferPassId(rootBufName) catch return error.createBufferManuelNoBufPassId;
        const bufDesc = try registry.getBufferDefinition(bufPassId);

        switch (bufDesc.share) {
            .transient => return error.ManualTextureCantBeTransient,
            else => {},
        }

        const subresCount = switch (bufDesc.update) {
            .Rarely => 1,
            .Often => rc.MAX_IN_FLIGHT,
            .PerFrame => rc.MAX_IN_FLIGHT,
        };

        var manualBuf = ManualBuf{ .updateTyp = bufDesc.update };
        for (0..subresCount) |_| {
            const bufId = try getFreeBufId(self);
            try manualBuf.subBufs.appendLast(bufId);
        }

        self.manualBufs.upsert(bufPassId, manualBuf);
    }

    fn createTextureManuel(self: *RenderAssignerData, registry: *const RenderRegistryData, rootTexName: []const u8, _: *RendererQueue, _: *MemoryManager) !void {
        const texPassId = registry.getTexturePassId(rootTexName) catch return error.createBufferManuelNoBufPassId;
        const texDesc = try registry.getTextureDefinition(texPassId);

        const subresCount = switch (texDesc.update) {
            .Rarely => 1,
            .Often => rc.MAX_IN_FLIGHT,
            .PerFrame => rc.MAX_IN_FLIGHT,
        };

        switch (texDesc.share) {
            .transient => return error.ManualTextureCantBeTransient,
            else => {},
        }
        if (texDesc.fitPass) return error.ManualTextureCantFitPass;

        var manualTex = ManualTex{ .updateTyp = texDesc.update };

        for (0..subresCount) |_| {
            const texId = try getFreeTexId(self);
            try manualTex.subTexes.appendLast(texId);
        }

        self.manualTexes.upsert(texPassId, manualTex);
    }

    fn ensureSubBuf(self: *RenderAssignerData, bufPassId: BufPassId, subId: BufId, bufDesc: BufDesc, rendererQueue: *RendererQueue) !void {
        const subBufExists = self.manualSubBufs.isKeyUsed(subId);

        if (subBufExists == false) {
            const bufInf = BufInf{
                .id = subId,
                .mem = bufDesc.mem,
                .elementSize = bufDesc.elementSize,
                .len = bufDesc.len,
                .typ = bufDesc.typ,
                .update = bufDesc.update,
                .resize = bufDesc.resize,
            };
            self.manualSubBufs.insert(subId, SubResBuffer{ .lastUsedFrame = self.assignedFrames, .bufInf = bufInf, .bufId = subId });
        }

        const bufInf = &self.manualSubBufs.getPtrByKey(subId).bufInf;

        if (self.bufUpdates.isKeyUsed(bufPassId)) {
            const bufUpdate = self.bufUpdates.getPtrByKey(bufPassId);
            const bytes = try convertToByteSlice(bufUpdate.data);

            if (try checkBufferResize(bufDesc.resize, bytes.len, bufInf.elementSize * bufInf.len) == true) {
                bufInf.len = @intCast(bytes.len / bufInf.elementSize);
                std.debug.print("6.Resource Assigner: Buf SubRes (BufId {}) ADJUSTED\n", .{subId.val()});

                if (subBufExists) {
                    try rendererQueue.append(.{ .removeBuffer = subId });
                    self.requests.append(.{ .destroyBuf = subId }) catch return error.RenderAssignerRequestsFull;
                    try rendererQueue.append(.{ .addBuffer = .{ .bufInf = bufInf.*, .data = null } });
                    self.requests.append(.{ .createBuf = subId }) catch return error.RenderAssignerRequestsFull;
                    std.debug.print("6.Resource Assigner: Buf SubRes (BufId {}) RECREATED\n", .{subId.val()});
                }
            }
        }

        if (subBufExists == false) {
            try rendererQueue.append(.{ .addBuffer = .{ .bufInf = bufInf.*, .data = null } });
            self.requests.append(.{ .createBuf = subId }) catch return error.RenderAssignerRequestsFull;
            std.debug.print("6.Resource Assigner: Buf SubRes (BufId {}) CREATED\n", .{subId.val()});
        }
    }

    fn ensureSubTex(self: *RenderAssignerData, texPassId: TexPassId, subId: TexId, texDesc: TexDesc, rendererQueue: *RendererQueue) !void {
        const subTexExists = self.manualSubTexes.isKeyUsed(subId);

        if (subTexExists == false) {
            const texInf = TexInf{
                .id = subId,
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
            self.manualSubTexes.insert(subId, SubResTexture{ .lastUsedFrame = self.assignedFrames, .texInf = texInf, .texId = subId });
        }
        const texInf = &self.manualSubTexes.getPtrByKey(subId).texInf;

        if (self.texUpdates.isKeyUsed(texPassId)) {
            if (self.texUpdates.getPtrByKey(texPassId).newExtent) |newExtent| {
                const oldExtent = vk.VkExtent3D{ .width = texInf.width, .height = texInf.height, .depth = texInf.depth };

                if (try checkTextureResize(texDesc.resize, oldExtent, newExtent) == true) {
                    texInf.width = newExtent.width;
                    texInf.height = newExtent.height;
                    texInf.depth = newExtent.depth;
                    std.debug.print("6.Resource Assigner: Tex SubRes (TexId {}) ADJUSTED ({}x{} to {}x{})\n", .{ subId.val(), oldExtent.width, oldExtent.height, texInf.width, texInf.height });

                    if (subTexExists) {
                        try rendererQueue.append(.{ .removeTexture = subId });
                        self.requests.append(.{ .destroyTex = subId }) catch return error.RenderAssignerRequestsFull;
                        try rendererQueue.append(.{ .addTexture = .{ .texInf = texInf.*, .data = null } });
                        self.requests.append(.{ .createTex = subId }) catch return error.RenderAssignerRequestsFull;
                        std.debug.print("6.Resource Assigner: Tex SubRes (TexId {}) RECREATED\n", .{subId.val()});
                    }
                }
            }
        }

        if (subTexExists == false) {
            try rendererQueue.append(.{ .addTexture = .{ .texInf = texInf.*, .data = null } });
            self.requests.append(.{ .createTex = subId }) catch return error.RenderAssignerRequestsFull;
            std.debug.print("6.Resource Assigner: Tex SubRes (TexId {}) CREATED\n", .{subId.val()});
        }
    }

    fn deleteBufferManuel(self: *RenderAssignerData, registry: *const RenderRegistryData, bufName: []const u8, _: *RendererQueue) !void {
        const bufPassId = registry.getBufferPassId(bufName) catch return error.deleteBufferManualNoBufPassId;
        if (self.manualBufs.isKeyUsed(bufPassId) == false) return error.DeleteBufferNotManual;

        const manualBuf = self.manualBufs.getPtrByKey(bufPassId);

        while (manualBuf.subBufs.removeFirstItem()) |subBufId| {
            if (self.manualSubBufs.isKeyUsed(subBufId) == true) {
                const lastUsedFrame = self.manualSubBufs.getByKey(subBufId).lastUsedFrame;
                self.manualSubBufs.remove(subBufId);
                try self.subBufDeletions.append(.{ .deletionFrame = lastUsedFrame + rc.MAX_IN_FLIGHT, .subBuf = subBufId });
            } else freeUpBufId(self, subBufId);
        }

        self.manualBufs.remove(bufPassId);
    }

    fn deleteTextureManuel(self: *RenderAssignerData, registry: *const RenderRegistryData, texName: []const u8, _: *RendererQueue) !void {
        const texPassId = registry.getTexturePassId(texName) catch return error.deleteTextureManualNoTexPassId;
        if (self.manualTexes.isKeyUsed(texPassId) == false) return error.DeleteBufferNotManual;

        const manualTex = self.manualTexes.getPtrByKey(texPassId);

        while (manualTex.subTexes.removeFirstItem()) |subTexId| {
            if (self.manualSubTexes.isKeyUsed(subTexId) == true) {
                const lastUsedFrame = self.manualSubTexes.getByKey(subTexId).lastUsedFrame;
                self.manualSubTexes.remove(subTexId);
                try self.subTexDeletions.append(.{ .deletionFrame = lastUsedFrame + rc.MAX_IN_FLIGHT, .subTex = subTexId });
            } else freeUpTexId(self, subTexId);
        }

        self.manualTexes.remove(texPassId);
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

    fn processQueue(self: *RenderAssignerData, registry: *const RenderRegistryData, assignerQueue: *RenderAssignerQueue, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        for (0..assignerQueue.length()) |i| {
            const event = assignerQueue.get(@intCast(i));
            switch (event) {
                .createManualBuffer => |bufName| try createBufferManuel(self, registry, bufName, rendererQueue, memoryMan),
                .deleteManualBuffer => |bufName| try deleteBufferManuel(self, registry, bufName, rendererQueue),
                .createManualTexture => |texName| try createTextureManuel(self, registry, texName, rendererQueue, memoryMan),
                .deleteManualTexture => |texName| try deleteTextureManuel(self, registry, texName, rendererQueue),

                .updateBuffer, .updateBufferSegment, .updateTexture => {},
            }
        }
    }

    fn sendUpdates(self: *RenderAssignerData, rendererQueue: *RendererQueue) !void {
        for (self.bufUpdates.getConstItems(), 0..) |bufUpdate, i| {
            const bufPassId = self.bufUpdates.getKeyByIndex(@intCast(i));

            const subBufId = self.bufAssigns.getByKey(bufPassId);
            self.requests.append(.{ .updateBuf = subBufId }) catch return error.RenderAssignerRequestsFull;
            try rendererQueue.append(.{ .updateBuffer = .{ .bufId = subBufId, .data = bufUpdate.data } });
        }

        for (self.texUpdates.getConstItems(), 0..) |texUpdate, i| {
            const texPassId = self.texUpdates.getKeyByIndex(@intCast(i));

            const subTexId = self.texAssigns.getByKey(texPassId);
            self.requests.append(.{ .updateTex = subTexId }) catch return error.RenderAssignerRequestsFull;
            try rendererQueue.append(.{ .updateTexture = .{ .texId = subTexId, .data = texUpdate.data, .newExtent = texUpdate.newExtent } });
        }
    }

    fn processUpdateQueue(self: *RenderAssignerData, registry: *const RenderRegistryData, assignerQueue: *RenderAssignerQueue, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        for (0..assignerQueue.length()) |i| {
            const event = assignerQueue.get(@intCast(i));
            switch (event) {
                .createManualBuffer, .deleteManualBuffer, .createManualTexture, .deleteManualTexture => {},

                .updateBuffer => |updateBuffer| {
                    const bufPassId = try registry.getBufferPassId(updateBuffer.bufName);
                    const bufDesc = try registry.getBufferDefinition(bufPassId);
                    if (self.manualBufs.isKeyUsed(bufPassId) == false) return error.BufferUpdateCantFindManual;

                    switch (bufDesc.update) {
                        .PerFrame, .Often => {},
                        .Rarely => {
                            const bufName = try registry.getBufferName(bufPassId);
                            try deleteBufferManuel(self, registry, bufName, rendererQueue);
                            try createBufferManuel(self, registry, bufName, rendererQueue, memoryMan);
                        },
                    }

                    self.bufUpdates.upsert(bufPassId, updateBuffer);
                },
                .updateBufferSegment => |_| {
                    return error.UpdateBufferSegmentIncorrectlyImplemented;
                },
                .updateTexture => |updateTexture| {
                    const texPassId = try registry.getTexturePassId(updateTexture.texName);
                    const texDesc = try registry.getTextureDefinition(texPassId);
                    if (self.manualTexes.isKeyUsed(texPassId) == false) return error.TextureUpdateCantFindManual;

                    switch (texDesc.update) {
                        .PerFrame, .Often => {},
                        .Rarely => {
                            const texName = try registry.getTextureName(texPassId);
                            try deleteTextureManuel(self, registry, texName, rendererQueue);
                            try createTextureManuel(self, registry, texName, rendererQueue, memoryMan);
                        },
                    }

                    self.texUpdates.upsert(texPassId, updateTexture);
                },
            }
        }
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

fn checkBufferResize(resize: vhE.ResizeType, newSize: u64, oldSize: u64) !bool {
    return switch (resize) {
        .Block => if (newSize > oldSize) error.BufferBaseTooSmallForUpdate else false,
        .Grow => newSize > oldSize,
        .Fit => newSize != oldSize,
    };
}

fn checkTextureResize(resize: vhE.ResizeType, old: vk.VkExtent3D, new: vk.VkExtent3D) !bool {
    return switch (resize) {
        .Block => if (old.width != new.width or old.height != new.height or old.depth != new.depth) return error.TextureResizeNotAllowedOnBlock else false,
        .Grow => old.width < new.width or old.height < new.height or old.depth < new.depth,
        .Fit => old.width != new.width or old.height != new.height or old.depth != new.depth,
    };
}

fn convertToByteSlice(data: anytype) ![]const u8 {
    const DataType = @TypeOf(data);
    return switch (@typeInfo(DataType)) {
        .optional => if (data) |d| convertToByteSlice(d) else error.ExpectedPointer,
        .pointer => |ptr| switch (ptr.size) {
            .one => std.mem.asBytes(data),
            .slice => std.mem.sliceAsBytes(data),
            else => return error.UnsupportedPointerType,
        },
        else => return error.ExpectedPointer,
    };
}
