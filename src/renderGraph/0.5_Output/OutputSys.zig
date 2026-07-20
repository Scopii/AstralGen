const RenderRegistryData = @import("../../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const CompositeNode = @import("../../render/types/pass/RenderNode.zig").CompositeNode;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const WindowId = @import("../../.configs/idConfig.zig").WindowId;
const Viewport = @import("../../viewport/Viewport.zig").Viewport;
const EngineData = @import("../../EngineData.zig").EngineData;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const OutputData = @import("OutputData.zig").OutputData;

// Step 1

pub const OutputSys = struct {
    pub fn build(self: *OutputData, registry: *const RenderRegistryData, data: *const EngineData) !void {
        self.texInputs.clear();
        self.bufInputs.clear();

        self.texInputRanges.clear();
        self.bufInputRanges.clear();

        self.texProducer.clear();
        self.bufProducer.clear();

        self.pendingPasses.clear();

        self.activePasses.clear();

        // Build: Fill All Resource Links
        for (registry.passDefinitions.getConstItems(), 0..) |passDef, i| {
            const passId = registry.passDefinitions.getKeyByIndex(@intCast(i));
            const texStart = self.texInputs.len;
            const bufStart = self.bufInputs.len;

            for (passDef.passAttribute.constSlice()) |attribute| {
                switch (attribute) {
                    inline else => |texAttribute| {
                        const inputId = try registry.getTexturePassId(texAttribute.texLink.in);
                        try self.texInputs.append(inputId);

                        if (texAttribute.texLink.out) |output| {
                            const outputId = try registry.getTexturePassId(output);
                            if (self.texProducer.isKeyUsed(outputId)) return error.TwoProducersForSameTex; // one-producer rule
                            self.texProducer.upsert(outputId, passId); // producers only
                        }
                    },
                    .bufSlot => |bufSlot| {
                        const inputId = try registry.getBufferPassId(bufSlot.bufLink.in);
                        try self.bufInputs.append(inputId);

                        if (bufSlot.bufLink.out) |output| {
                            const outputId = try registry.getBufferPassId(output);
                            if (self.bufProducer.isKeyUsed(outputId) == true) return error.TwoProducersForSameTex; // one-producer rule
                            self.bufProducer.upsert(outputId, passId); // producers only
                        }
                    },
                    .bufLinking => |bufLink| {
                        const inputId = try registry.getBufferPassId(bufLink.in);
                        try self.bufInputs.append(inputId);

                        // if (bufLink.out) |output| {
                        //     const outputId = try registry.getBufferPassId(output);
                        //     if (self.bufProducer.isKeyUsed(outputId) == true) return error.TwoProducersForSameTex; // one-producer rule
                        //     self.bufProducer.upsert(outputId, passId); // producers only
                        // }
                    },
                    .texLinking => |texLink| {
                        const inputId = try registry.getTexturePassId(texLink.in);
                        try self.texInputs.append(inputId);

                        // if (texLink.out) |output| {
                        //     const outputId = try registry.getTexturePassId(output);
                        //     if (self.texProducer.isKeyUsed(outputId) == true) return error.TwoProducersForSameTex; // one-producer rule
                        //     self.texProducer.upsert(outputId, passId); // producers only
                        // }
                    },
                    //
                    .vertexBuffer, .indexBuffer, .vertexAttribute, .renderState, .shaderInf => {},
                }
            }

            self.texInputRanges.upsert(passId, .{ .first = @intCast(texStart), .last = @intCast(self.texInputs.len) });
            self.bufInputRanges.upsert(passId, .{ .first = @intCast(bufStart), .last = @intCast(self.bufInputs.len) });
        }

        // Load producing passes of each viewports composite source
        for (data.viewport.activeViewportIds.getConstItems()) |viewportId| {
            const viewport = data.viewport.viewports.getByKey(viewportId.val());

            for (viewport.stringComposites) |stringComposite| {
                const texPassId = try registry.getTexturePassId(stringComposite);
                if (self.texProducer.isKeyUsed(texPassId) == false) {
                    std.debug.print("ERROR: 0.5 OutputSys: Texture Output ({s}) has no producer\n", .{stringComposite});
                    return error.CompositeSourceHasNoProducer;
                }
                const texProducer = self.texProducer.getByKey(texPassId);
                try self.pendingPasses.append(texProducer);
            }
        }

        while (self.pendingPasses.len != 0) {
            const passId = self.pendingPasses.pop().?;
            if (self.activePasses.isKeyUsed(passId)) continue; // dedupe + cycle guard
            self.activePasses.upsert(passId, passId);

            const texRange = self.texInputRanges.getByKey(passId);
            for (self.texInputs.constSlice()[texRange.first..texRange.last]) |texPassid| {
                if (self.texProducer.isKeyUsed(texPassid) == false) continue; // Skip no Producer
                const texProducer = self.texProducer.getByKey(texPassid);
                try self.pendingPasses.append(texProducer);
            }

            const bufRange = self.bufInputRanges.getByKey(passId);
            for (self.bufInputs.constSlice()[bufRange.first..bufRange.last]) |bufPassId| {
                if (self.bufProducer.isKeyUsed(bufPassId) == false) continue; // Skip no Producer
                const bufProducer = self.bufProducer.getByKey(bufPassId);
                try self.pendingPasses.append(bufProducer);
            }
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("0.5.Output: \n", .{});
            for (self.activePasses.getConstItems()) |passId| {
                const passName = try registry.getPassName(passId);
                std.debug.print(" - Pass: {s}\n", .{passName});
            }
            std.debug.print("\n", .{});
        }
    }
};
