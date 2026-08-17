const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const PassRefRange = @import("../renderGraph/components.zig").PassRefRange;
const TexReference = @import("../renderGraph/components.zig").TexReference;
const BufReference = @import("../renderGraph/components.zig").BufReference;
const LinkedIdMap = @import("../.structures/LinkedIdMap.zig").LinkedIdMap;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const BufRefId = @import("../.configs/idConfig.zig").BufRefId;
const TexRefId = @import("../.configs/idConfig.zig").TexRefId;
const PassId = @import("../.configs/idConfig.zig").PassId;
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

pub const PassLoadData = struct {
    bufRanges: LinkedIdMap(PassRefRange, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
    bufRefs: FixedList(BufReference, rc.PASS_MAX * rc.BUF_MAX) = .{},

    texRanges: LinkedIdMap(PassRefRange, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
    texRefs: FixedList(TexReference, rc.PASS_MAX * rc.TEX_MAX) = .{},
};

pub const PassLoadSys = struct {
    pub fn build(self: *PassLoadData, registry: *const RenderRegistryData) !void {
        self.bufRanges.clear();
        self.bufRefs.clear();

        self.texRanges.clear();
        self.texRefs.clear();

        for (registry.passDefinitions.getConstItems(), 0..) |passDef, i| {
            const passId = registry.passDefinitions.getKeyByIndex(@intCast(i));
            const texStart = self.texRefs.len;
            const bufStart = self.bufRefs.len;

            for (passDef.passAttribute.constSlice()) |attribute| {
                switch (attribute) {
                    .vertexAttribute, .renderState, .shaderInf => {},

                    .bufSlot => |bufSlot| {
                        const bufPassId = try registry.getBufferPassId(bufSlot.bufLink.in);
                        const rootPassId = if (bufSlot.bufLink.from) |rootPass| try registry.getPassId(rootPass) else null;
                        const bufRef = BufReference{ .bufPassId = bufPassId, .passId = passId, .rootPassId = rootPassId, .access = if (bufSlot.access.isReadOnly() == true) .read else .write };
                        try self.bufRefs.append(bufRef);
                    },
                    .vertexBuffer => |bufSlot| {
                        const bufPassId = try registry.getBufferPassId(bufSlot.bufInput);
                        const bufRef = BufReference{ .bufPassId = bufPassId, .passId = passId, .rootPassId = null, .access = .read }; // Read should be verified!
                        try self.bufRefs.append(bufRef);
                    },
                    .indexBuffer => |bufSlot| {
                        const bufPassId = try registry.getBufferPassId(bufSlot.bufInput);
                        const bufRef = BufReference{ .bufPassId = bufPassId, .passId = passId, .rootPassId = null, .access = .read }; // Read should be verified!
                        try self.bufRefs.append(bufRef);
                    },

                    .texLinking => |texLink| {
                        const texPassId = try registry.getTexturePassId(texLink.in);
                        const rootPassId = if (texLink.from) |rootPass| try registry.getPassId(rootPass) else null;
                        const texRef = TexReference{ .texPassId = texPassId, .passId = passId, .rootPassId = rootPassId, .access = .read };
                        try self.texRefs.append(texRef);
                    }, // ? Should not create Physical
                    .bufLinking => |bufLink| {
                        const bufPassId = try registry.getBufferPassId(bufLink.in);
                        const rootPassId = if (bufLink.from) |rootPass| try registry.getPassId(rootPass) else null;
                        const bufRef = BufReference{ .bufPassId = bufPassId, .passId = passId, .rootPassId = rootPassId, .access = .read };
                        try self.bufRefs.append(bufRef);
                    }, // ? Should not create Physical

                    .texSlot => |texSlotTypes| {
                        const texPassId = try registry.getTexturePassId(texSlotTypes.texLink.in);
                        const rootPassId = if (texSlotTypes.texLink.from) |rootPass| try registry.getPassId(rootPass) else null;
                        const texRef = TexReference{ .texPassId = texPassId, .passId = passId, .rootPassId = rootPassId, .access = if (texSlotTypes.access.isReadOnly() == true) .read else .write };
                        try self.texRefs.append( texRef);
                    },
                    .colorAtt => |texSlotTypes| {
                        const texPassId = try registry.getTexturePassId(texSlotTypes.texLink.in);
                        const rootPassId = if (texSlotTypes.texLink.from) |rootPass| try registry.getPassId(rootPass) else null;
                        const texRef = TexReference{ .texPassId = texPassId, .passId = passId, .rootPassId = rootPassId, .access = if (texSlotTypes.access.isReadOnly() == true) .read else .write };
                        try self.texRefs.append(texRef);
                    },
                    .depthAtt, .stencilAtt => |texSlotTypes| {
                        const texPassId = try registry.getTexturePassId(texSlotTypes.texLink.in);
                        const rootPassId = if (texSlotTypes.texLink.from) |rootPass| try registry.getPassId(rootPass) else null;
                        const texRef = TexReference{ .texPassId = texPassId, .passId = passId, .rootPassId = rootPassId, .access = if (texSlotTypes.access.isReadOnly() == true) .read else .write };
                        try self.texRefs.append(texRef);
                    },
                }
            }

            self.texRanges.upsert(passId, .{ .first = @intCast(texStart), .last = @intCast(self.texRefs.len) });
            self.bufRanges.upsert(passId, .{ .first = @intCast(bufStart), .last = @intCast(self.bufRefs.len) });
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("1.PassLoad: \n", .{});
            for (self.bufRanges.getConstItems(), 0..) |bufRange, index| {
                const passId = self.bufRanges.getKeyByIndex(@intCast(index));
                const passName = try registry.getPassName(passId);
                std.debug.print(" - Pass {s}\n", .{passName});

                const texRange = self.texRanges.getByIndex(@intCast(index));

                for (self.bufRefs.constSlice()[bufRange.first..bufRange.last]) |bufRef| {
                    const bufName = try registry.getBufferName(bufRef.bufPassId);
                    const rootPassName = if (bufRef.rootPassId) |rootPassId| try registry.getPassName(rootPassId) else "NULL";
                    std.debug.print("    -> Buf ( .name = {s}, .from = {s} )\n", .{ bufName, rootPassName });
                }

                for (self.texRefs.constSlice()[texRange.first..texRange.last]) |texRef| {
                    const texName = try registry.getTextureName(texRef.texPassId);
                    const rootPassName = if (texRef.rootPassId) |rootPassId| try registry.getPassName(rootPassId) else "NULL";
                    std.debug.print("    -> Tex ( .name = {s}, .from = {s} )\n", .{ texName, rootPassName });
                }
            }
            std.debug.print("\n", .{});
        }
    }
};
