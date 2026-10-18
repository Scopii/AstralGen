const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const LinkedIdMap = @import("../.structures/LinkedIdMap.zig").LinkedIdMap;
const BufLifetime = @import("../renderGraph/components.zig").BufLifetime;
const TexLifetime = @import("../renderGraph/components.zig").TexLifetime;
const DependencyData = @import("3.5_Dependency.zig").DependencyData;
const OptimizerData = @import("6_Optimizer.zig").OptimizerData;
const ResourceData = @import("5.5_Resource.zig").ResourceData;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

pub const LifetimeData = struct {
    bufLifetimeMap: LinkedIdMap(BufLifetime, rc.BUF_MAX, BufPassId, rc.BUF_MAX, 0) = .{},
    texLifetimeMap: LinkedIdMap(TexLifetime, rc.TEX_MAX, TexPassId, rc.TEX_MAX, 0) = .{},

    bufLifetimes: FixedList(BufLifetime, rc.BUF_MAX) = .{},
    texLifetimes: FixedList(TexLifetime, rc.TEX_MAX) = .{},
};

pub const LifetimeSys = struct {
    pub fn build(self: *LifetimeData, dependency: *const DependencyData, resource: *const ResourceData, optimizer: *const OptimizerData, registry: *const RenderRegistryData) !void {
        self.bufLifetimeMap.clear();
        self.texLifetimeMap.clear();
        self.bufLifetimes.clear();
        self.texLifetimes.clear();

        // Buffer Lifetimes
        for (dependency.activeBufRefs.constSlice()) |bufRef| {
            const bufPassId = bufRef.bufPassId;
            const passPosition = optimizer.optimizedGraph.getIndexByKey(bufRef.passId);

            if (self.bufLifetimeMap.isKeyUsed(bufPassId) == false) {
                self.bufLifetimeMap.upsert(bufPassId, BufLifetime{ .bufPassId = bufPassId, .earliestPass = passPosition, .latestPass = passPosition });
            } else {
                var lifetime = self.bufLifetimeMap.getPtrByKey(bufPassId);
                if (passPosition < lifetime.earliestPass) lifetime.earliestPass = passPosition;
                if (passPosition > lifetime.latestPass) lifetime.latestPass = passPosition;
            }
        }

        // Only Append Transient
        for (self.bufLifetimeMap.getConstItems(), 0..) |bufLifetime, index| {
            const bufPassId = self.bufLifetimeMap.getKeyByIndex(@intCast(index));
            if (resource.activeBufDescs.getByKey(bufPassId).share == .transient) try self.bufLifetimes.append(bufLifetime);
        }

        self.bufLifetimes.selectionSort(greaterGroup);
        // self.bufLifetimes.defeatingQuicksort(lessThanGroup);

        // Texture Lifetimes
        for (dependency.activeTexRefs.constSlice()) |texRef| {
            const texPassId = texRef.texPassId;
            const passPosition = optimizer.optimizedGraph.getIndexByKey(texRef.passId);

            if (self.texLifetimeMap.isKeyUsed(texPassId) == false) {
                self.texLifetimeMap.upsert(texPassId, TexLifetime{ .texPassId = texPassId, .earliestPass = passPosition, .latestPass = passPosition });
            } else {
                var lifetime = self.texLifetimeMap.getPtrByKey(texPassId);
                if (passPosition < lifetime.earliestPass) lifetime.earliestPass = passPosition;
                if (passPosition > lifetime.latestPass) lifetime.latestPass = passPosition;
            }
        }

        // Only Append Transient
        for (self.texLifetimeMap.getConstItems(), 0..) |texLifetime, index| {
            const bufPassId = self.texLifetimeMap.getKeyByIndex(@intCast(index));
            if (resource.activeTexDescs.getByKey(bufPassId).share == .transient) try self.texLifetimes.append(texLifetime);
        }

        self.texLifetimes.selectionSort(greaterGroup);
        // self.texLifetimes.defeatingQuicksort(lessThanGroup);

        // Debug
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("7.Lifetime: \n", .{});

            for (self.bufLifetimeMap.getConstItems(), 0..) |bufLifetime, index| {
                const bufPassId = self.bufLifetimeMap.getKeyByIndex(@intCast(index));
                const bufName = try registry.getBufferName(bufPassId);

                const earliestPass = optimizer.optimizedGraph.getConstItems()[bufLifetime.earliestPass].passId;
                const latestPass = optimizer.optimizedGraph.getConstItems()[bufLifetime.latestPass].passId;
                const earliestName = try registry.getPassName(earliestPass);
                const latestName = try registry.getPassName(latestPass);
                std.debug.print("- Transient Buf Lifetime ({s}): ({} -> {}) ({s} -> {s})\n", .{ bufName, bufLifetime.earliestPass, bufLifetime.latestPass, earliestName, latestName });
            }

            for (self.texLifetimeMap.getConstItems(), 0..) |texLifetime, index| {
                const texPassId = self.texLifetimeMap.getKeyByIndex(@intCast(index));
                const texName = try registry.getTextureName(texPassId);

                const earliestPass = optimizer.optimizedGraph.getConstItems()[texLifetime.earliestPass].passId;
                const latestPass = optimizer.optimizedGraph.getConstItems()[texLifetime.latestPass].passId;
                const earliestName = try registry.getPassName(earliestPass);
                const latestName = try registry.getPassName(latestPass);
                std.debug.print("- Transient Tex Lifetime ({s}): ({} -> {}) ({s} -> {s})\n", .{ texName, texLifetime.earliestPass, texLifetime.latestPass, earliestName, latestName });
            }
            std.debug.print("\n", .{});
        }
    }
};

fn lessThanGroup(group1: anytype, group2: anytype) bool {
    if (group1.earliestPass != group2.earliestPass) return group1.earliestPass < group2.earliestPass;
    return group1.latestPass < group2.latestPass;
}

fn greaterGroup(group1: anytype, group2: anytype) bool {
    if (group1.earliestPass != group2.earliestPass) return group1.earliestPass > group2.earliestPass;
    return group1.latestPass > group2.latestPass;
}
