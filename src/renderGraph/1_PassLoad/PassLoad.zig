const RenderRegistryData = @import("../../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const PassAccessRange = @import("../../renderGraph/components.zig").PassAccessRange;
const TexInstance = @import("../../renderGraph/components.zig").TexInstance;
const BufInstance = @import("../../renderGraph/components.zig").BufInstance;
const LinkedIdMap = @import("../../.structures/LinkedIdMap.zig").LinkedIdMap;
const BufInstanceId = @import("../../.configs/idConfig.zig").BufInstanceId;
const TexInstanceId = @import("../../.configs/idConfig.zig").TexInstanceId;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

pub const PassLoadData = struct {
    bufRanges: LinkedIdMap(PassAccessRange, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
    bufInstances: LinkedIdMap(BufInstance, rc.PASS_MAX * rc.BUF_MAX, BufInstanceId, rc.PASS_MAX * rc.BUF_MAX, 0) = .{},

    texRanges: LinkedIdMap(PassAccessRange, rc.PASS_MAX, PassId, rc.PASS_MAX, 0) = .{},
    texInstances: LinkedIdMap(TexInstance, rc.PASS_MAX * rc.TEX_MAX, TexInstanceId, rc.PASS_MAX * rc.TEX_MAX, 0) = .{},
};

pub const PassLoadSys = struct {
    pub fn build(self: *PassLoadData, registry: *const RenderRegistryData) !void {
        self.bufRanges.clear();
        self.bufInstances.clear();

        self.texRanges.clear();
        self.texInstances.clear();

        for (registry.passDefinitions.getConstItems(), 0..) |passDef, i| {
            const passId = registry.passDefinitions.getKeyByIndex(@intCast(i));
            const texStart = self.texInstances.getLength();
            const bufStart = self.bufInstances.getLength();

            for (passDef.passAttribute.constSlice()) |attribute| {
                switch (attribute) {
                    .vertexAttribute, .renderState, .shaderInf => {},

                    .bufSlot => |bufSlot| {
                        const bufPassId = try registry.getBufferPassId(bufSlot.bufLink.in);
                        const rootPassId = if (bufSlot.bufLink.from) |rootPass| try registry.getPassId(rootPass) else null;
                        const bufInst = BufInstance{ .bufPassId = bufPassId, .passId = passId, .rootPassId = rootPassId, .access = if (bufSlot.access.isReadOnly() == true) .read else .write };
                        const curLength: u16 = @intCast(self.bufInstances.getLength());
                        self.bufInstances.insert(.id(curLength), bufInst);
                    },

                    inline .vertexBuffer, .indexBuffer => |bufSlot| {
                        const bufPassId = try registry.getBufferPassId(bufSlot.bufInput);
                        const bufInst = BufInstance{ .bufPassId = bufPassId, .passId = passId, .rootPassId = null, .access = .read }; // Read should be verified!
                        const curLength: u16 = @intCast(self.bufInstances.getLength());
                        self.bufInstances.insert(.id(curLength), bufInst);
                    },

                    .texLinking => |texLink| {
                        const texPassId = try registry.getTexturePassId(texLink.in);
                        const rootPassId = if (texLink.from) |rootPass| try registry.getPassId(rootPass) else null;
                        const texInst = TexInstance{ .texPassId = texPassId, .passId = passId, .rootPassId = rootPassId, .access = .read };
                        const curLength: u16 = @intCast(self.texInstances.getLength());
                        self.texInstances.insert(.id(curLength), texInst);
                    }, // ? Should not create Physical
                    .bufLinking => |bufLink| {
                        const bufPassId = try registry.getBufferPassId(bufLink.in);
                        const rootPassId = if (bufLink.from) |rootPass| try registry.getPassId(rootPass) else null;
                        const bufInst = BufInstance{ .bufPassId = bufPassId, .passId = passId, .rootPassId = rootPassId, .access = .read };
                        const curLength: u16 = @intCast(self.bufInstances.getLength());
                        self.bufInstances.insert(.id(curLength), bufInst);
                    }, // ? Should not create Physical

                    inline else => |texSlotTypes| {
                        const texPassId = try registry.getTexturePassId(texSlotTypes.texLink.in);
                        const rootPassId = if (texSlotTypes.texLink.from) |rootPass| try registry.getPassId(rootPass) else null;
                        const texInst = TexInstance{ .texPassId = texPassId, .passId = passId, .rootPassId = rootPassId, .access = if (texSlotTypes.access.isReadOnly() == true) .read else .write };
                        const curLength: u16 = @intCast(self.texInstances.getLength());
                        self.texInstances.insert(.id(curLength), texInst);
                    },
                }
            }

            self.texRanges.upsert(passId, .{ .first = @intCast(texStart), .last = @intCast(self.texInstances.getLength()) });
            self.bufRanges.upsert(passId, .{ .first = @intCast(bufStart), .last = @intCast(self.bufInstances.getLength()) });
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("1.PassLoad: \n", .{});
            for (self.bufRanges.getConstItems(), 0..) |bufRange, index| {
                const passId = self.bufRanges.getKeyByIndex(@intCast(index));
                const passName = try registry.getPassName(passId);
                std.debug.print(" - Pass {s}\n", .{passName});

                const texRange = self.texRanges.getByIndex(@intCast(index));

                for (self.bufInstances.getConstItems()[bufRange.first..bufRange.last]) |bufInstance| {
                    const bufName = try registry.getBufferName(bufInstance.bufPassId);
                    const rootPassName = if (bufInstance.rootPassId) |rootPassId| try registry.getPassName(rootPassId) else "NULL";
                    std.debug.print("    -> Buf ( .name = {s}, .from = {s} )\n", .{ bufName, rootPassName });
                }

                for (self.texInstances.getConstItems()[texRange.first..texRange.last]) |texInstance| {
                    const texName = try registry.getTextureName(texInstance.texPassId);
                    const rootPassName = if (texInstance.rootPassId) |rootPassId| try registry.getPassName(rootPassId) else "NULL";
                    std.debug.print("    -> Tex ( .name = {s}, .from = {s} )\n", .{ texName, rootPassName });
                }
            }
            std.debug.print("\n", .{});
        }
    }
};
