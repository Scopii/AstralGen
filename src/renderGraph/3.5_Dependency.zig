const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const TexReference = @import("../renderGraph/components.zig").TexReference;
const BufReference = @import("../renderGraph/components.zig").BufReference;
const SimpleIdMap = @import("../.structures/SimpleIdMap.zig").SimpleIdMap;
const LinkedIdMap = @import("../.structures/LinkedIdMap.zig").LinkedIdMap;
const Dependancy = @import("../renderGraph/components.zig").Dependency;
const FixedList = @import("../.structures/FixedList.zig").FixedList;
const TexDesc = @import("../render/types/res/Texture.zig").TexDesc;
const OutputLoadData = @import("2_OutputLoad.zig").OutputLoadData;
const BufDesc = @import("../render/types/res/Buffer.zig").BufDesc;
const CompositeData = @import("5.2_Composite.zig").CompositeData;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const PassLoadData = @import("1_PassLoad.zig").PassLoadData;
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

pub const DependencyData = struct {
    activeTexRefs: FixedList(TexReference, rc.PASS_MAX * rc.TEX_MAX) = .{},
    activeBufRefs: FixedList(BufReference, rc.PASS_MAX * rc.BUF_MAX) = .{},

    dependencies: FixedList(Dependancy, rc.PASS_MAX * rc.RESOURCE_MAX) = .{},
};

pub const DependencySys = struct {
    pub fn build(self: *DependencyData, passLoad: *const PassLoadData, outputLoad: *const OutputLoadData, registry: *const RenderRegistryData, debug: bool) !void {
        self.activeBufRefs.clear();
        self.activeTexRefs.clear();
        self.dependencies.clear();

        for (outputLoad.activePasses.getConstItems()) |activePass| {
            // All Dependency Orderings
            const depRange = passLoad.dependencyRanges.getByKey(activePass);
            const dependencys = passLoad.dependencys.constSlice()[depRange.first..depRange.last];
            for (dependencys) |dep| {
                if (outputLoad.activePasses.isKeyUsed(dep.predecessor) == false) continue; // optional passes are filtered
                try self.dependencies.append(dep);
            }

            // Buffers
            const bufRange = passLoad.bufRanges.getByKey(activePass);
            const bufRefs = passLoad.bufRefs.constSlice()[bufRange.first..bufRange.last];
            for (bufRefs) |bufRef| {
                if (bufRef.rootPassId) |rootPassId| try self.dependencies.append(.{ .predecessor = rootPassId, .successor = bufRef.passId });
                try self.activeBufRefs.append(bufRef);
            }

            // Textures
            const texRange = passLoad.texRanges.getByKey(activePass);
            const texRefs = passLoad.texRefs.constSlice()[texRange.first..texRange.last];
            for (texRefs) |texRef| {
                if (texRef.rootPassId) |rootPassId| try self.dependencies.append(.{ .predecessor = rootPassId, .successor = texRef.passId });
                try self.activeTexRefs.append(texRef);
            }
        }



        // Debug Output
        if (debug) {
            std.debug.print("3.5.DependencySys: \n", .{});
            for (self.dependencies.constSlice(), 0..) |dep, index| {
                const predName = try registry.getPassName(dep.predecessor);
                const succName = try registry.getPassName(dep.successor);
                std.debug.print("    {}. {s} -> {s}\n", .{ index, predName, succName });
            }
            std.debug.print("\n", .{});
        }
    }
};
