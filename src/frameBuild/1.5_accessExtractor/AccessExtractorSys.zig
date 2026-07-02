const PassDefinition = @import("../../render/types/pass/PassDefinition.zig").PassDefinition;
const PassAccessRange = @import("../../frameBuild/components.zig").PassAccessRange;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const ResourceRegistryData = @import("../0_resourceRegistry/ResourceRegistryData.zig").ResourceRegistryData;
const PassExtractorData = @import("../1_passExtractor/PassExtractorData.zig").PassExtractorData;
const AccessExtractorData = @import("AccessExtractorData.zig").AccessExtractorData;

// Step 1.5

pub const AccessExtractorSys = struct {
    pub fn buildAccesses(accessExtractor: *AccessExtractorData, passExtractor: *const PassExtractorData, resourceRegistry: *const ResourceRegistryData) !void {
        accessExtractor.bufAccesses.clear();
        accessExtractor.texAccesses.clear();

        for (0..passExtractor.activePasses.getLength()) |index| {
            const passId = passExtractor.activePasses.getByIndex(@intCast(index));
            const passDef = try resourceRegistry.getPassDefinitionById(passId);

            const firstBufIndex = accessExtractor.bufAccesses.len;
            const firstTexIndex = accessExtractor.texAccesses.len;

            for (passDef.passAttribute.constSlice()) |attribute| {
                switch (attribute) {
                    .bufSlot => |bufSlot| {
                        accessExtractor.bufAccesses.append(.{
                            .pass = passId,
                            .bufInput = try resourceRegistry.getBufferPassId(bufSlot.bufLink.in),
                            .bufOutput = if (bufSlot.bufLink.out) |output| try resourceRegistry.getBufferPassId(output) else null,
                            .access = if (bufSlot.access.isReadOnly() == true) .read else .write,
                        }) catch return error.PassCoreLinksFull;
                    },
                    .vertexBuffer => |vertexBufSlot| {
                        accessExtractor.bufAccesses.append(.{
                            .pass = passId,
                            .bufInput = try resourceRegistry.getBufferPassId(vertexBufSlot.bufInput),
                            .bufOutput = null,
                            .access = .read,
                        }) catch return error.PassCoreLinksFull;
                    },
                    .indexBuffer => |indexBufSlot| {
                        accessExtractor.bufAccesses.append(.{
                            .pass = passId,
                            .bufInput = try resourceRegistry.getBufferPassId(indexBufSlot.bufInput),
                            .bufOutput = null,
                            .access = .read,
                        }) catch return error.PassCoreLinksFull;
                    },
                    .vertexAttribute, .renderState, .execution, .shaderInf => {},
                    inline else => |texSlotTypes| {
                        accessExtractor.texAccesses.append(.{
                            .pass = passId,
                            .texInput = try resourceRegistry.getTexturePassId(texSlotTypes.texLink.in),
                            .texOutput = if (texSlotTypes.texLink.out) |output| try resourceRegistry.getTexturePassId(output) else null,
                            .access = if (texSlotTypes.access.isReadOnly() == true) .read else .write,
                        }) catch return error.PassCoreLinksFull;
                    },
                }
            }

            // Pass Access Ranges
            const passAccessRanges = PassAccessRange{
                .firstBuf = @intCast(firstBufIndex),
                .firstTex = @intCast(firstTexIndex),
                .lastBuf = @intCast(accessExtractor.bufAccesses.len),
                .lastTex = @intCast(accessExtractor.texAccesses.len),
            };

            accessExtractor.passAccessRanges.upsert(passId.val(), passAccessRanges);
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("1.5.ResourceExtractor: \n", .{});

            for (accessExtractor.passAccessRanges.getConstItems(), 0..) |range, i| {
                const passKey = accessExtractor.passAccessRanges.getKeyByIndex(@intCast(i));
                const passString = try resourceRegistry.getPassName(.id(passKey));

                std.debug.print(" - Pass Accesses ({s}) (bufIndex {} -> {}) (texIndex {} -> {})\n", .{ passString, range.firstBuf, range.lastBuf, range.firstTex, range.lastTex });
                for (range.firstBuf..range.lastBuf, 0..) |index, counter| {
                    const bufAccess = accessExtractor.bufAccesses.buffer[index];
                    const inputName = try resourceRegistry.getBufferName(bufAccess.bufInput);
                    const outputName = if (bufAccess.bufOutput) |output| try resourceRegistry.getBufferName(output) else "null";
                    const access = @tagName(bufAccess.access);
                    const passName = try resourceRegistry.getPassName(bufAccess.pass);
                    std.debug.print("     -> Buf {}. ( .pass = {s}, .bufInput = {s}, .bufOutput = {s}, .access = {s})\n", .{ counter, passName, inputName, outputName, access });
                }
                for (range.firstTex..range.lastTex, 0..) |index, counter| {
                    const texAccess = accessExtractor.texAccesses.buffer[index];
                    const inputName = try resourceRegistry.getTextureName(texAccess.texInput);
                    const outputName = if (texAccess.texOutput) |output| try resourceRegistry.getTextureName(output) else "null";
                    const access = @tagName(texAccess.access);
                    const passName = try resourceRegistry.getPassName(texAccess.pass);
                    std.debug.print("     -> Tex {}. ( .pass = {s}, .texInput = {s}, .texOutput = {s}, .access = {s})\n", .{ counter, passName, inputName, outputName, access });
                }
            }
            std.debug.print("\n", .{});
        }
    }
};
