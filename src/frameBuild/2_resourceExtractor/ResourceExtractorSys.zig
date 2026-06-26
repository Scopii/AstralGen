const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const PassAccessRange = @import("../../frameBuild/components.zig").PassAccessRange;
const TextureAccess = @import("../../frameBuild/components.zig").TextureAccess;
const BufferAccess = @import("../../frameBuild/components.zig").BufferAccess;
const PassDef = @import("../../render/types/pass/PassDef.zig").PassDef;
const TexPassId = @import("../components.zig").TexPassId;
const BufPassId = @import("../components.zig").BufPassId;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const ResourceExtractorData = @import("ResourceExtractorData.zig").ResourceExtractorData;
const ResourceRegistryData = @import("../0_resourceRegistry/ResourceRegistryData.zig").ResourceRegistryData;
const PassExtractorData = @import("../1_passExtractor/PassExtractorData.zig").PassExtractorData;

// Step 2

pub const ResourceExtractorSys = struct {
    pub fn buildAccesses(resourceExtractor: *ResourceExtractorData, passExtractor: *const PassExtractorData, resourceRegistry: *const ResourceRegistryData) !void {
        resourceExtractor.bufAccesses.clear();
        resourceExtractor.texAccesses.clear();

        resourceExtractor.bufDescriptions.clear();
        resourceExtractor.texDescriptions.clear();

        resourceExtractor.bufMemSize.clear();
        resourceExtractor.texMemSize.clear();

        resourceExtractor.passAccessRanges.clear();

        for (0..passExtractor.renderNodes.getLength()) |index| {
            const renderNode = passExtractor.renderNodes.getByIndex(@intCast(index));

            switch (renderNode) {
                .passNode => |pass| {
                    const key = passExtractor.renderNodes.getKeyByIndex(@intCast(index));
                    getPassAccesses(&pass.pass, resourceExtractor, key);
                },
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
            const bufKey1: u16 = bufAccess.bufInput.val();
            if (resourceExtractor.bufDescriptions.isKeyUsed(bufKey1) == false) {
                const bufDesc1 = try resourceRegistry.getBufferDefinition(bufAccess.bufInput);
                resourceExtractor.bufDescriptions.upsert(bufKey1, bufDesc1);

                // If Description is Share = Transient add memSize
                if (bufDesc1.share == .transient) resourceExtractor.bufMemSize.upsert(bufKey1, bufDesc1.guessMemoryCost());
            }

            // For Output
            const bufKey2: ?u16 = if (bufAccess.bufOutput) |bufOutput| bufOutput.val() else null;
            if (bufKey2) |key2| {
                if (resourceExtractor.bufDescriptions.isKeyUsed(key2) == false) {
                    const bufDesc2 = try resourceRegistry.getBufferDefinition(bufAccess.bufOutput.?);
                    resourceExtractor.bufDescriptions.upsert(key2, bufDesc2);

                    // If Description is Share = Transient add memSize
                    if (bufDesc2.share == .transient) resourceExtractor.bufMemSize.upsert(key2, bufDesc2.guessMemoryCost());
                }
            }
        }

        // Resolve and Save Texture Descriptions
        for (resourceExtractor.texAccesses.constSlice()) |texAccess| {
            // For Input
            const texKey1: u16 = texAccess.texInput.val();
            if (resourceExtractor.texDescriptions.isKeyUsed(texKey1) == false) {
                const texDesc1 = try resourceRegistry.getTextureDefinition(texAccess.texInput);
                resourceExtractor.texDescriptions.upsert(texKey1, texDesc1);

                // If Description is Share = Transient add memSize
                if (texDesc1.share == .transient) resourceExtractor.texMemSize.upsert(texKey1, texDesc1.guessMemoryCost());
            }

            // For Output
            const texKey2: ?u16 = if (texAccess.texOutput) |texOutput| texOutput.val() else null;
            if (texKey2) |key2| {
                if (resourceExtractor.texDescriptions.isKeyUsed(key2) == false) {
                    const texDesc2 = try resourceRegistry.getTextureDefinition(texAccess.texOutput.?);
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
                const passString = passExtractor.passStrings.getByKey(passKey);

                std.debug.print(" - Pass Accesses ({s}) (bufIndex {} -> {}) (texIndex {} -> {})\n", .{ passString, range.firstBuf, range.lastBuf, range.firstTex, range.lastTex });
                for (range.firstBuf..range.lastBuf, 0..) |index, counter| {
                    const bufAccess = resourceExtractor.bufAccesses.buffer[index];
                    const inputName = try resourceRegistry.getBufferName(bufAccess.bufInput);
                    const outputName = if (bufAccess.bufOutput) |output| try resourceRegistry.getBufferName(output) else "null";
                    const access = @tagName(bufAccess.access);
                    std.debug.print("     -> Buf {}. ( .pass = {}, .bufInput = {s}, .bufOutput = {s}, .access = {s})\n", .{ counter, bufAccess.pass, inputName, outputName, access });
                }
                for (range.firstTex..range.lastTex, 0..) |index, counter| {
                    const texAccess = resourceExtractor.texAccesses.buffer[index];
                    const inputName = try resourceRegistry.getTextureName(texAccess.texInput);
                    const outputName = if (texAccess.texOutput) |output| try resourceRegistry.getTextureName(output) else "null";
                    const access = @tagName(texAccess.access);
                    std.debug.print("     -> Tex {}. ( .pass = {}, .texInput = {s}, .texOutput = {s}, .access = {s})\n", .{ counter, texAccess.pass, inputName, outputName, access });
                }
            }
            std.debug.print("\n", .{});
        }

        // Debug Output 2
        if (rc.FRAME_GRAPH_DEBUG) {
            // Buffer Mem Debug
            for (resourceExtractor.bufMemSize.getConstItems(), 0..) |memSize, i| {
                const bufKey: u16 = resourceExtractor.bufMemSize.getKeyByIndex(@intCast(i));
                const bufName = try resourceRegistry.getBufferName(.id(bufKey));
                std.debug.print(" {}.Buf ({s}) -> Mem {} Bytes\n", .{ i, bufName, memSize });
            }
            // Texture Mem Debug
            for (resourceExtractor.texMemSize.getConstItems(), 0..) |memSize, i| {
                const texKey: u16 = resourceExtractor.texMemSize.getKeyByIndex(@intCast(i));
                const texName = try resourceRegistry.getTextureName(.id(texKey));
                std.debug.print(" {}.Tex ({s}) -> Mem {} Bytes\n", .{ i, texName, memSize });
            }
            std.debug.print("\n", .{});
        }
    }

    fn getPassAccesses(pass: *const PassDef, resourceExtractor: *ResourceExtractorData, passId: u16) void {
        const firstBufIndex = resourceExtractor.bufAccesses.len;
        const firstTexIndex = resourceExtractor.texAccesses.len;

        // Buffers Use Cases
        inline for (.{
            pass.getBufUses(),
        }) |slice| {
            for (slice) |use| {
                const bufAccess = BufferAccess{
                    .access = if (use.access.isReadOnly() == true) .read else .write,
                    .pass = .id(passId),
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
                    .pass = .id(passId),
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
                    .pass = .id(passId),
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

        resourceExtractor.passAccessRanges.upsert(passId, passAccessRanges);
    }
};
