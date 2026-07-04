const PassAccessRange = @import("../../frameBuild/components.zig").PassAccessRange;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const PassData = @import("../1_Pass/PassData.zig").PassData;
const AccessData = @import("AccessData.zig").AccessData;

// Step 1.5

pub const AccessSys = struct {
    pub fn build(accessData: *AccessData, passData: *const PassData, registryData: *const RegistryData) !void {
        accessData.accesses.clear();

        for (0..passData.activePasses.getLength()) |index| {
            const passId = passData.activePasses.getByIndex(@intCast(index));
            const passDef = try registryData.getPassDefinitionById(passId);

            const start = accessData.accesses.len;

            // ONLY BUFFER ACCESSES
            for (passDef.passAttribute.constSlice()) |attribute| {
                switch (attribute) {
                    .bufSlot => |bufSlot| {
                        accessData.accesses.append(.{
                            .pass = passId,
                            .input = .{ .bufPassId = try registryData.getBufferPassId(bufSlot.bufLink.in) },
                            .output = if (bufSlot.bufLink.out) |output| .{ .bufPassId = try registryData.getBufferPassId(output) } else null,
                            .access = if (bufSlot.access.isReadOnly() == true) .read else .write,
                        }) catch return error.PassCoreLinksFull;
                    },
                    .vertexBuffer => |vertexBufSlot| {
                        accessData.accesses.append(.{
                            .pass = passId,
                            .input = .{ .bufPassId = try registryData.getBufferPassId(vertexBufSlot.bufInput) },
                            .output = null,
                            .access = .read,
                        }) catch return error.PassCoreLinksFull;
                    },
                    .indexBuffer => |indexBufSlot| {
                        accessData.accesses.append(.{
                            .pass = passId,
                            .input = .{ .bufPassId = try registryData.getBufferPassId(indexBufSlot.bufInput) },
                            .output = null,
                            .access = .read,
                        }) catch return error.PassCoreLinksFull;
                    },
                    .texLinking => |texLink| {
                        accessData.accesses.append(.{
                            .pass = passId,
                            .input = .{ .texPassId = try registryData.getTexturePassId(texLink.in) },
                            .output = if (texLink.out) |output| .{ .texPassId = try registryData.getTexturePassId(output) } else null,
                            .access = .read,
                        }) catch return error.PassCoreLinksFull;
                    },
                    .bufLinking => |bufLink| {
                        accessData.accesses.append(.{
                            .pass = passId,
                            .input = .{ .bufPassId = try registryData.getBufferPassId(bufLink.in) },
                            .output = if (bufLink.out) |output| .{ .bufPassId = try registryData.getBufferPassId(output) } else null,
                            .access = .read,
                        }) catch return error.PassCoreLinksFull;
                    },
                    .vertexAttribute, .renderState, .execution, .shaderInf => {},
                    inline else => |texSlotTypes| {
                        accessData.accesses.append(.{
                            .pass = passId,
                            .input = .{ .texPassId = try registryData.getTexturePassId(texSlotTypes.texLink.in) },
                            .output = if (texSlotTypes.texLink.out) |output| .{ .texPassId = try registryData.getTexturePassId(output) } else null,
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
                const pass = try registryData.getPassName(passKey);
                std.debug.print(" - Pass Accesses ({s}) (Access Index {} -> {})\n", .{ pass, range.first, range.last });

                for (range.first..range.last, 0..) |index, counter| {
                    const access = accessData.accesses.buffer[index];
                    const inputName = switch (access.input) {
                        .bufPassId => |id| try registryData.getBufferName(id),
                        .texPassId => |id| try registryData.getTextureName(id),
                    };
                    const outputName = if (access.output) |output| switch (output) {
                        .bufPassId => |id| try registryData.getBufferName(id),
                        .texPassId => |id| try registryData.getTextureName(id),
                    } else "null";
                    const passName = try registryData.getPassName(access.pass);
                    const inputTag = @tagName(access.input);
                    const accessTag = @tagName(access.access);
                    std.debug.print("     -> {s} {}. ( .pass = {s}, .input = {s}, .output = {s}, .access = {s})\n", .{ inputTag, counter, passName, inputName, outputName, accessTag });
                }
            }
            std.debug.print("\n", .{});
        }
    }
};
