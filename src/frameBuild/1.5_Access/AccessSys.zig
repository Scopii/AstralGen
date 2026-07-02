const PassDefinition = @import("../../render/types/pass/PassDefinition.zig").PassDefinition;
const PassAccessRange = @import("../../frameBuild/components.zig").PassAccessRange;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const PassData = @import("../1_Pass/PassData.zig").PassData;
const AccessData = @import("AccessData.zig").AccessData;

// Step 1.5

pub const AccessSys = struct {
    pub fn buildAccesses(accessData: *AccessData, passData: *const PassData, registryData: *const RegistryData) !void {
        accessData.bufAccesses.clear();
        accessData.texAccesses.clear();

        for (0..passData.activePasses.getLength()) |index| {
            const passId = passData.activePasses.getByIndex(@intCast(index));
            const passDef = try registryData.getPassDefinitionById(passId);

            const bufStart = accessData.bufAccesses.len;
            const texStart = accessData.texAccesses.len;

            for (passDef.passAttribute.constSlice()) |attribute| {
                switch (attribute) {
                    .bufSlot => |bufSlot| {
                        accessData.bufAccesses.append(.{
                            .pass = passId,
                            .bufInput = try registryData.getBufferPassId(bufSlot.bufLink.in),
                            .bufOutput = if (bufSlot.bufLink.out) |output| try registryData.getBufferPassId(output) else null,
                            .access = if (bufSlot.access.isReadOnly() == true) .read else .write,
                        }) catch return error.PassCoreLinksFull;
                    },
                    .vertexBuffer => |vertexBufSlot| {
                        accessData.bufAccesses.append(.{
                            .pass = passId,
                            .bufInput = try registryData.getBufferPassId(vertexBufSlot.bufInput),
                            .bufOutput = null,
                            .access = .read,
                        }) catch return error.PassCoreLinksFull;
                    },
                    .indexBuffer => |indexBufSlot| {
                        accessData.bufAccesses.append(.{
                            .pass = passId,
                            .bufInput = try registryData.getBufferPassId(indexBufSlot.bufInput),
                            .bufOutput = null,
                            .access = .read,
                        }) catch return error.PassCoreLinksFull;
                    },
                    .vertexAttribute, .renderState, .execution, .shaderInf => {},
                    inline else => |texSlotTypes| {
                        accessData.texAccesses.append(.{
                            .pass = passId,
                            .texInput = try registryData.getTexturePassId(texSlotTypes.texLink.in),
                            .texOutput = if (texSlotTypes.texLink.out) |output| try registryData.getTexturePassId(output) else null,
                            .access = if (texSlotTypes.access.isReadOnly() == true) .read else .write,
                        }) catch return error.PassCoreLinksFull;
                    },
                }
            }

            // Pass Access Ranges
            const accessRanges = PassAccessRange{
                .firstBuf = @intCast(bufStart),
                .firstTex = @intCast(texStart),
                .lastBuf = @intCast(accessData.bufAccesses.len),
                .lastTex = @intCast(accessData.texAccesses.len),
            };
            accessData.passAccessRanges.upsert(passId.val(), accessRanges);
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("1.5.ResourceExtractor: \n", .{});

            for (accessData.passAccessRanges.getConstItems(), 0..) |range, i| {
                const passKey = accessData.passAccessRanges.getKeyByIndex(@intCast(i));
                const passString = try registryData.getPassName(.id(passKey));

                std.debug.print(" - Pass Accesses ({s}) (bufIndex {} -> {}) (texIndex {} -> {})\n", .{ passString, range.firstBuf, range.lastBuf, range.firstTex, range.lastTex });
                for (range.firstBuf..range.lastBuf, 0..) |index, counter| {
                    const bufAccess = accessData.bufAccesses.buffer[index];
                    const input = try registryData.getBufferName(bufAccess.bufInput);
                    const output = if (bufAccess.bufOutput) |output| try registryData.getBufferName(output) else "null";
                    const access = @tagName(bufAccess.access);
                    const bufPass = try registryData.getPassName(bufAccess.pass);
                    std.debug.print("     -> Buf {}. ( .pass = {s}, .bufInput = {s}, .bufOutput = {s}, .access = {s})\n", .{ counter, bufPass, input, output, access });
                }
                for (range.firstTex..range.lastTex, 0..) |index, counter| {
                    const texAccess = accessData.texAccesses.buffer[index];
                    const input = try registryData.getTextureName(texAccess.texInput);
                    const output = if (texAccess.texOutput) |output| try registryData.getTextureName(output) else "null";
                    const access = @tagName(texAccess.access);
                    const texPass = try registryData.getPassName(texAccess.pass);
                    std.debug.print("     -> Tex {}. ( .pass = {s}, .texInput = {s}, .texOutput = {s}, .access = {s})\n", .{ counter, texPass, input, output, access });
                }
            }
            std.debug.print("\n", .{});
        }
    }
};
