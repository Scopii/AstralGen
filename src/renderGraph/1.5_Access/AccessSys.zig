const RenderRegistryData = @import("../../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const PassAccessRange = @import("../../renderGraph/components.zig").PassAccessRange;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const getResTyp = @import("../components.zig").getResTyp;
const bufToRes = @import("../components.zig").bufToRes;
const texToRes = @import("../components.zig").texToRes;

const PassData = @import("../1_Pass/PassData.zig").PassData;
const AccessData = @import("AccessData.zig").AccessData;

// Step 1.5

pub const AccessSys = struct {
    pub fn build(accessData: *AccessData, passData: *const PassData, registry: *const RenderRegistryData) !void {
        accessData.accesses.clear();

        for (0..passData.activePasses.getLength()) |index| {
            const passId = passData.activePasses.getByIndex(@intCast(index));
            const passDef = try registry.getPassDefinitionById(passId);

            const start = accessData.accesses.len;

            // ONLY BUFFER ACCESSES
            for (passDef.passAttribute.constSlice()) |attribute| {
                switch (attribute) {
                    .bufSlot => |bufSlot| {
                        accessData.accesses.append(.{
                            .pass = passId,
                            .input = bufToRes(try registry.getBufferPassId(bufSlot.bufLink.in)),
                            .output = if (bufSlot.bufLink.out) |output| bufToRes(try registry.getBufferPassId(output)) else null,
                            .access = if (bufSlot.access.isReadOnly() == true) .read else .write,
                        }) catch return error.PassCoreLinksFull;
                    },
                    .vertexBuffer => |vertexBufSlot| {
                        accessData.accesses.append(.{
                            .pass = passId,
                            .input = bufToRes(try registry.getBufferPassId(vertexBufSlot.bufInput)),
                            .output = null,
                            .access = .read,
                        }) catch return error.PassCoreLinksFull;
                    },
                    .indexBuffer => |indexBufSlot| {
                        accessData.accesses.append(.{
                            .pass = passId,
                            .input = bufToRes(try registry.getBufferPassId(indexBufSlot.bufInput)),
                            .output = null,
                            .access = .read,
                        }) catch return error.PassCoreLinksFull;
                    },
                    .texLinking => |texLink| {
                        accessData.accesses.append(.{
                            .pass = passId,
                            .input = texToRes(try registry.getTexturePassId(texLink.in)),
                            .output = if (texLink.out) |output| texToRes(try registry.getTexturePassId(output)) else null,
                            .access = .read,
                        }) catch return error.PassCoreLinksFull;
                    },
                    .bufLinking => |bufLink| {
                        accessData.accesses.append(.{
                            .pass = passId,
                            .input = bufToRes(try registry.getBufferPassId(bufLink.in)),
                            .output = if (bufLink.out) |output| bufToRes(try registry.getBufferPassId(output)) else null,
                            .access = .read,
                        }) catch return error.PassCoreLinksFull;
                    },
                    .vertexAttribute, .renderState, .execution, .shaderInf => {},
                    inline else => |texSlotTypes| {
                        accessData.accesses.append(.{
                            .pass = passId,
                            .input = texToRes(try registry.getTexturePassId(texSlotTypes.texLink.in)),
                            .output = if (texSlotTypes.texLink.out) |output| texToRes(try registry.getTexturePassId(output)) else null,
                            .access = if (texSlotTypes.access.isReadOnly() == true) .read else .write,
                        }) catch return error.PassCoreLinksFull;
                    },
                }
            }
            // Pass Access Ranges
            accessData.accessRanges.upsert(passId, PassAccessRange{ .first = @intCast(start), .last = @intCast(accessData.accesses.len) });
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("1.5.ResourceExtractor: \n", .{});

            for (accessData.accessRanges.getConstItems(), 0..) |range, i| {
                const passKey = accessData.accessRanges.getKeyByIndex(@intCast(i));
                const pass = try registry.getPassName(passKey);
                std.debug.print(" - Pass Accesses ({s}) (Access Index {} -> {})\n", .{ pass, range.first, range.last });

                for (range.first..range.last, 0..) |index, counter| {
                    const access = accessData.accesses.buffer[index];

                    const inputTyp = getResTyp(access.input);
                    const inputName = try registry.getResourceName(access.input);
                    const outputName = if (access.output) |output| try registry.getResourceName(output) else "null";

                    const passName = try registry.getPassName(access.pass);
                    std.debug.print("     -> {s} {}. ( .pass = {s}, .input = {s}, .output = {s}, .access = {s})\n", .{ @tagName(inputTyp), counter, passName, inputName, outputName, @tagName(access.access) });
                }
            }
            std.debug.print("\n", .{});
        }
    }
};
