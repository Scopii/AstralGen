const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const PassRefRange = @import("../renderGraph/components.zig").PassRefRange;
const TexReference = @import("../renderGraph/components.zig").TexReference;
const BufReference = @import("../renderGraph/components.zig").BufReference;
const LinkedIdMap = @import("../.structures/LinkedIdMap.zig").LinkedIdMap;
const Dependency = @import("../renderGraph/components.zig").Dependency;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const TexUsage = @import("../render/help/Enums.zig").TexUsage;
const PassId = @import("../.configs/idConfig.zig").PassId;
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

pub const PassLoadData = struct {
    bufRanges: LinkedIdMap(PassRefRange, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
    bufRefs: FixedList(BufReference, rc.PASS_MAX * rc.BUF_MAX) = .{},

    texRanges: LinkedIdMap(PassRefRange, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
    texRefs: FixedList(TexReference, rc.PASS_MAX * rc.TEX_MAX) = .{},

    texUsages: LinkedIdMap(TexUsage, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    dependencyRanges: LinkedIdMap(PassRefRange, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
    dependencys: FixedList(Dependency, rc.PASS_MAX * 10) = .{}, // 10 is a reasonable guess!
};

pub const PassLoadSys = struct {
    pub fn build(self: *PassLoadData, registry: *const RenderRegistryData) !void {
        self.bufRanges.clear();
        self.bufRefs.clear();

        self.texRanges.clear();
        self.texRefs.clear();

        self.texUsages.clear();

        self.dependencyRanges.clear();
        self.dependencys.clear();

        for (registry.passes.getConstItems(), 0..) |passDef, i| {
            const passId = registry.passes.getKeyByIndex(@intCast(i));
            const texStart = self.texRefs.len;
            const bufStart = self.bufRefs.len;
            const depStart = self.dependencys.len;

            for (passDef.passProperties.constSlice()) |attribute| {
                switch (attribute) {
                    .vertexAttribute, .renderState, .shaderInf => {},

                    .bufSlot => |bufSlot| {
                        const rootPassId = bufSlot.bufLink.from orelse null;
                        const bufRef = BufReference{ .bufPassId = bufSlot.bufLink.in, .passId = passId, .rootPassId = rootPassId, .access = if (bufSlot.access.isReadOnly()) .read else .write };
                        try self.bufRefs.append(bufRef);
                    },

                    .vertexBuffer => |vertSlot| {
                        const bufRef = BufReference{ .bufPassId = vertSlot.bufPassId, .passId = passId, .rootPassId = null, .access = .read }; // Read should be verified!
                        try self.bufRefs.append(bufRef);
                    },

                    .indexBuffer => |indexSlot| {
                        const bufRef = BufReference{ .bufPassId = indexSlot.bufPassId, .passId = passId, .rootPassId = null, .access = .read }; // Read should be verified!
                        try self.bufRefs.append(bufRef);
                    },

                    inline .texLink, .bufLink => |texLink| {
                        if (texLink.from) |rootPass| {
                            try self.dependencys.append(Dependency{ .predecessor = rootPass, .successor = passId });
                        } else return error.LinkOrderingWithoutFrom;
                    },
                    .passLink => |passDep| {
                        try self.dependencys.append(Dependency{ .predecessor = passDep, .successor = passId });
                    },

                    .colorAtt => |texSlotTypes| {
                        const texPassId = texSlotTypes.texLink.in;

                        const texRef = TexReference{
                            .texPassId = texSlotTypes.texLink.in,
                            .passId = passId,
                            .rootPassId = texSlotTypes.texLink.from,
                            .access = if (texSlotTypes.access.isReadOnly()) .read else .write,
                        };
                        try self.texRefs.append(texRef);

                        if (self.texUsages.isKeyUsed(texPassId) == true) {
                            const curUsage = self.texUsages.getPtrByKey(texPassId);
                            curUsage.colorAtt = true;
                            curUsage.sampled = true;
                        } else {
                            self.texUsages.insert(texPassId, .{ .colorAtt = true, .sampled = true });
                        }
                    },

                    .texSlot => |texSlotTypes| {
                        const texPassId = texSlotTypes.texLink.in;

                        const texRef = TexReference{
                            .texPassId = texSlotTypes.texLink.in,
                            .passId = passId,
                            .rootPassId = texSlotTypes.texLink.from,
                            .access = if (texSlotTypes.access.isReadOnly()) .read else .write,
                        };
                        try self.texRefs.append(texRef);

                        if (self.texUsages.isKeyUsed(texPassId) == true) {
                            const curUsage = self.texUsages.getPtrByKey(texPassId);
                            curUsage.sampled = true;
                            if (texSlotTypes.descUse == .Storage) curUsage.storage = true;
                        } else {
                            if (texSlotTypes.descUse == .Storage) self.texUsages.insert(texPassId, .{ .storage = true, .sampled = true }) else self.texUsages.insert(texPassId, .{ .sampled = true });
                        }
                    },

                    inline .depthAtt, .stencilAtt => |texSlotTypes| {
                        const texPassId = texSlotTypes.texLink.in;

                        const texRef = TexReference{
                            .texPassId = texSlotTypes.texLink.in,
                            .passId = passId,
                            .rootPassId = texSlotTypes.texLink.from,
                            .access = if (texSlotTypes.access.isReadOnly()) .read else .write,
                        };
                        try self.texRefs.append(texRef);

                        if (self.texUsages.isKeyUsed(texPassId) == true) {
                            const curUsage = self.texUsages.getPtrByKey(texPassId);
                            curUsage.sampled = true;
                            curUsage.depthAtt = true;
                        } else {
                            self.texUsages.insert(texPassId, .{ .depthAtt = true, .sampled = true });
                        }
                    },
                }
            }

            self.texRanges.upsert(passId, .{ .first = @intCast(texStart), .last = @intCast(self.texRefs.len) });
            self.bufRanges.upsert(passId, .{ .first = @intCast(bufStart), .last = @intCast(self.bufRefs.len) });

            self.dependencyRanges.upsert(passId, .{ .first = @intCast(depStart), .last = @intCast(self.dependencys.len) });
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("1.PassLoad: \n", .{});
            for (self.bufRanges.getConstItems(), 0..) |bufRange, index| {
                const passId = self.bufRanges.getKeyByIndex(@intCast(index));
                const passName = try registry.getPassName(passId);
                std.debug.print(" - Pass {s}\n", .{passName});

                const texRange = self.texRanges.getByIndex(@intCast(index));
                const depRange = self.dependencyRanges.getByIndex(@intCast(index));

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

                for (self.dependencys.constSlice()[depRange.first..depRange.last]) |dep| {
                    const predName = try registry.getPassName(dep.predecessor);
                    const succName = try registry.getPassName(dep.successor);
                    std.debug.print("    -> ORDER ONLY ( .predecessor = {s}, .successor = {s} )\n", .{ predName, succName });
                }
            }
            std.debug.print("\n", .{});
        }
    }
};
