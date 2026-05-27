const TextureAccess = @import("../../frameBuild/components.zig").TextureAccess;
const BufferAccess = @import("../../frameBuild/components.zig").BufferAccess;
const PassAccessRange = @import("../../frameBuild/components.zig").PassAccessRange;
const PassDef = @import("../../render/types/pass/PassDef.zig").PassDef;
const PassEnum = @import("../../frameBuild/enums.zig").PassEnum;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const ResourceExtractorData = @import("ResourceExtractorData.zig").ResourceExtractorData;
const PassExtractorData = @import("../1_passExtractor/PassExtractorData.zig").PassExtractorData;

// Step 2

pub const ResourceExtractorSys = struct {
    pub fn buildAccesses(resourceExtractor: *ResourceExtractorData, passExtractor: *const PassExtractorData) !void {
        resourceExtractor.bufAccesses.clear();
        resourceExtractor.texAccesses.clear();

        resourceExtractor.passAccessRanges.clear();

        for (passExtractor.renderNodes.constSlice()) |*renderNode| {
            switch (renderNode.*) {
                .passNode => |pass| {
                    getPassAccesses(&pass.pass, resourceExtractor);
                },
                .compositeNode => |_| {},
                .viewportBlit => |_| {},
                .uiNode => |_| {},
                .clearBuffer, .clearTexture => return error.ClearBufferOrTextureIllegal,
                .barrierBakeClears => return error.BakeBarriersIllegal,
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
    }

    fn getPassAccesses(pass: *const PassDef, resourceExtractor: *ResourceExtractorData) void {
        const firstBufIndex = resourceExtractor.bufAccesses.len;
        const firstTexIndex = resourceExtractor.texAccesses.len;

        // Any Buffers Use Case
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

        // Any Texture Use Case
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

        // Append Pass Access Ranges
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
