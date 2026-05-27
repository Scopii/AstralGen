const TextureAccess = @import("../../frameBuild/components.zig").TextureAccess;
const BufferAccess = @import("../../frameBuild/components.zig").BufferAccess;
const PassAccessRange = @import("../../frameBuild/components.zig").PassAccessRange;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const PassDef = @import("../../render/types/pass/PassDef.zig").PassDef;
const PassEnum = @import("../../frameBuild/enums.zig").PassEnum;
const TextureEnum = @import("../enums.zig").TextureEnum;
const BufferEnum = @import("../enums.zig").BufferEnum;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const ResourceExtractorData = @import("ResourceExtractorData.zig").ResourceExtractorData;
const PassExtractorData = @import("../1_passExtractor/PassExtractorData.zig").PassExtractorData;

// Step 2

pub const ResourceExtractorSys = struct {
    pub fn buildAccesses(resourceExtractor: *ResourceExtractorData, passExtractor: *const PassExtractorData) !void {
        resourceExtractor.bufAccesses.clear();
        resourceExtractor.texAccesses.clear();

        resourceExtractor.bufDescriptions.clear();
        resourceExtractor.texDescriptions.clear();

        resourceExtractor.bufMemSize.clear();
        resourceExtractor.texMemSize.clear();

        resourceExtractor.passAccessRanges.clear();

        for (passExtractor.renderNodes.constSlice()) |*renderNode| {
            switch (renderNode.*) {
                .passNode => |pass| getPassAccesses(&pass.pass, resourceExtractor),
                .compositeNode => |_| {},
                .viewportBlit => |_| {},
                .uiNode => |_| {},
                .clearBuffer, .clearTexture => return error.ClearBufferOrTextureIllegal,
                .barrierBakeClears => return error.BakeBarriersIllegal,
            }
        }

        // Resolve and Save Buffer Descriptions
        for (resourceExtractor.bufAccesses.constSlice()) |bufAccess| {
            // For Input
            const bufKey1: u16 = @intCast(@intFromEnum(bufAccess.bufInput));
            if (resourceExtractor.bufDescriptions.isKeyUsed(bufKey1) == false) {
                const bufDesc1 = try resolveBufferEnum(bufAccess.bufInput);
                resourceExtractor.bufDescriptions.upsert(bufKey1, bufDesc1);

                // If Description is Share = Transient add memSize
                if (bufDesc1.share == .transient) resourceExtractor.bufMemSize.upsert(bufKey1, bufDesc1.guessMemoryCost());
            }

            // For Output
            const bufKey2: ?u16 = if (bufAccess.bufOutput) |bufOutput| @intCast(@intFromEnum(bufOutput)) else null;
            if (bufKey2) |key2| {
                if (resourceExtractor.bufDescriptions.isKeyUsed(key2) == false) {
                    const bufDesc2 = try resolveBufferEnum(bufAccess.bufOutput.?);
                    resourceExtractor.bufDescriptions.upsert(key2, bufDesc2);

                    // If Description is Share = Transient add memSize
                    if (bufDesc2.share == .transient) resourceExtractor.bufMemSize.upsert(key2, bufDesc2.guessMemoryCost());
                }
            }
        }

        // Resolve and Save Texture Descriptions
        for (resourceExtractor.texAccesses.constSlice()) |texAccess| {
            // For Input
            const texKey1: u16 = @intCast(@intFromEnum(texAccess.texInput));
            if (resourceExtractor.texDescriptions.isKeyUsed(texKey1) == false) {
                const texDesc1 = try resolveTextureEnum(texAccess.texInput);
                resourceExtractor.texDescriptions.upsert(texKey1, texDesc1);

                // If Description is Share = Transient add memSize
                if (texDesc1.share == .transient) resourceExtractor.texMemSize.upsert(texKey1, texDesc1.guessMemoryCost());
            }

            // For Output
            const texKey2: ?u16 = if (texAccess.texOutput) |texOutput| @intCast(@intFromEnum(texOutput)) else null;
            if (texKey2) |key2| {
                if (resourceExtractor.texDescriptions.isKeyUsed(key2) == false) {
                    const texDesc2 = try resolveTextureEnum(texAccess.texOutput.?);
                    resourceExtractor.texDescriptions.upsert(key2, texDesc2);

                    // If Description is Share = Transient add memSize
                    if (texDesc2.share == .transient) resourceExtractor.texMemSize.upsert(key2, texDesc2.guessMemoryCost());
                }
            }
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("2.ResourceExtractor: \n", .{});

            for (resourceExtractor.passAccessRanges.getConstItems(), 0..) |range, i| {
                const passKey = resourceExtractor.passAccessRanges.getKeyByIndex(@intCast(i));
                const passEnum: PassEnum = @enumFromInt(passKey);

                std.debug.print(" - Pass Accesses ({s}) (bufIndex {} -> {}) (texIndex {} -> {})\n", .{ @tagName(passEnum), range.firstBuf, range.lastBuf, range.firstTex, range.lastTex });
                for (range.firstBuf..range.lastBuf, 0..) |index, counter| {
                    const bufAccess = resourceExtractor.bufAccesses.buffer[index];
                    std.debug.print("     -> Buf {}. {}\n", .{ counter, bufAccess });
                }
                for (range.firstTex..range.lastTex, 0..) |index, counter| {
                    const texAccess = resourceExtractor.texAccesses.buffer[index];
                    std.debug.print("     -> Tex {}. {}\n", .{ counter, texAccess });
                }
            }
            std.debug.print("\n", .{});
        }

        // Debug Output 2
        if (rc.FRAME_GRAPH_DEBUG) {
            // Buffer Mem Debug
            for (resourceExtractor.bufMemSize.getConstItems(), 0..) |memSize, i| {
                const castedIndex: u32 = @intCast(i);
                const bufKey: u32 = resourceExtractor.bufMemSize.getKeyByIndex(castedIndex);
                const bufEnum: BufferEnum = @enumFromInt(bufKey);
                std.debug.print(" {}.Buf ({s}) -> Mem {} Bytes\n", .{ i, @tagName(bufEnum), memSize });
            }
            // Texture Mem Debug
            for (resourceExtractor.texMemSize.getConstItems(), 0..) |memSize, i| {
                const castedIndex: u32 = @intCast(i);
                const texKey: u32 = resourceExtractor.texMemSize.getKeyByIndex(castedIndex);
                const texEnum: TextureEnum = @enumFromInt(texKey);
                std.debug.print(" {}.Tex ({s}) -> Mem {} Bytes\n", .{ i, @tagName(texEnum), memSize });
            }
            std.debug.print("\n", .{});
        }
    }

    fn getPassAccesses(pass: *const PassDef, resourceExtractor: *ResourceExtractorData) void {
        const firstBufIndex = resourceExtractor.bufAccesses.len;
        const firstTexIndex = resourceExtractor.texAccesses.len;

        // Buffers Use Cases
        inline for (.{
            pass.getBufUses(),
        }) |slice| {
            for (slice) |use| {
                const bufAccess = BufferAccess{
                    .access = if (use.access.isReadOnly() == true) .read else .write,
                    .passEnum = pass.name,
                    .bufInput = use.bufLink.in,
                    .bufOutput = use.bufLink.out,
                };
                resourceExtractor.bufAccesses.append(bufAccess) catch std.debug.print("ERROR: Resource Extractor bufAccesses append failed!\n", .{});
            }
        }

        // Special Buffer Use Cases
        inline for (.{
            pass.getVertexBufUse(),
            if (pass.indexBuffer) |indexBuf| &.{indexBuf} else &.{},
        }) |slice| {
            for (slice) |use| {
                const bufAccess = BufferAccess{
                    .access = .read,
                    .passEnum = pass.name,
                    .bufInput = use.bufInput,
                    .bufOutput = null, // True Index and Vertex Buffers dont have Output!
                };
                resourceExtractor.bufAccesses.append(bufAccess) catch std.debug.print("ERROR: Resource Extractor bufAccesses append failed!\n", .{});
            }
        }

        // Texture Use Cases
        inline for (.{
            pass.getTexUses(),
            pass.getColorAtts(),
            if (pass.depthAtt) |depthAtt| &.{depthAtt} else &.{},
            if (pass.stencilAtt) |stencilAtt| &.{stencilAtt} else &.{},
        }) |slice| {
            for (slice) |use| {
                const texAccess = TextureAccess{
                    .access = if (use.access.isReadOnly() == true) .read else .write,
                    .passEnum = pass.name,
                    .texInput = use.texLink.in,
                    .texOutput = use.texLink.out,
                };
                resourceExtractor.texAccesses.append(texAccess) catch std.debug.print("ERROR: Resource Extractor texAccesses append failed!\n", .{});
            }
        }

        // Pass Access Ranges
        const passAccessRanges = PassAccessRange{
            .firstBuf = @intCast(firstBufIndex),
            .firstTex = @intCast(firstTexIndex),
            .lastBuf = @intCast(resourceExtractor.bufAccesses.len),
            .lastTex = @intCast(resourceExtractor.texAccesses.len),
        };
        const passKey = @intFromEnum(pass.name);

        resourceExtractor.passAccessRanges.upsert(@intCast(passKey), passAccessRanges);
    }
};

pub fn resolveTextureEnum(texEnum: TextureEnum) !TexDesc {
    return switch (texEnum) {
        // Cull stuff Missing

        .RayMarchInputTex => rc.rayMarchTexDesc,

        .GridTex => rc.gridTexDesc,
        .GridDepthTex => rc.gridDepthTexDesc,

        .DebugGridInputTex, .DebugGridOutputTex => rc.debugGridTexDesc,
        .DebugGridDepthTex, .DebugGridDepthOutputTex => rc.debugGridDepthTexDesc,

        .PlaneTex => rc.planeTexDesc,
        .PlaneDepthTex => rc.planeDepthTexDesc,

        .DebugPlaneInputTex, .DebugPlaneOutputTex, .DebugPlaneOutputFrustumViewTex => rc.debugPlaneTexDesc,
        .DebugPlaneDepthTex => rc.debugPlaneDepthTexDesc,

        .DepthViewTex => rc.depthViewTexDesc,

        .TestTileTex => rc.testTilesTexDesc,
        .ImguiFontTex => rc.imguiFontTexDesc,

        .Swapchain => return error.TextureEnumHasNoDescription,
    };
}

pub fn resolveBufferEnum(bufEnum: BufferEnum) !BufDesc {
    return switch (bufEnum) {
        .QuantIndirectInputSB, .QuantIndirectOutputSB => rc.indirectSBDesc,
        .ReadbackSB => rc.readbackSBDesc,

        .EntitySB => rc.entitySBDesc,
        .MainCamUB => rc.mainCamUBDesc,
        .DebugCamUB => rc.debugCamUBDesc,

        .ImguiVB => rc.imguiVBDesc,
        .ImguiIB => rc.imguiIBDesc,
    };
}
