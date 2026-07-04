const Dependancy = @import("../../frameBuild/components.zig").Dependancy;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const getResKey = @import("../../frameBuild/components.zig").getResKey;

const DependancyData = @import("DependancyData.zig").DependancyData;
const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const AccessData = @import("../1.5_Access/AccessData.zig").AccessData;

// Step 3

pub const DependancySys = struct {
    pub fn build(dependancyData: *DependancyData, accessData: *const AccessData, registryData: *const RegistryData) !void {
        dependancyData.deps.clear();
        dependancyData.lastWriter.clear();

        for (accessData.accesses.constSlice()) |access| {
            if (access.output) |output| {
                const resKey = getResKey(output);
                // Double Write Check: Only allowed exactly one producer!
                if (dependancyData.lastWriter.isKeyUsed(resKey) == true) {
                    const prevWriter = dependancyData.lastWriter.getByKey(resKey);
                    const prevName = try registryData.getPassName(prevWriter);
                    const newName = try registryData.getPassName(access.pass);

                    const resName = switch (output) {
                        .bufPassId => |id| try registryData.getBufferName(id),
                        .texPassId => |id| try registryData.getTextureName(id),
                    };
                    std.debug.print("VALIDATION: {s} {s} produced by both {s} and {s}\n", .{ @tagName(output), resName, prevName, newName });
                }
                dependancyData.lastWriter.upsert(resKey, access.pass);
            }
        }

        for (accessData.accesses.constSlice()) |access| {
            const resKey = getResKey(access.input);
            if (dependancyData.lastWriter.isKeyUsed(resKey) == true) {
                // Graph Edge only if its a cross pass dependancy (Pass does not consume its own resourcve)
                const inputPass = dependancyData.lastWriter.getByKey(resKey);
                if (inputPass != access.pass) {
                    const dep = Dependancy{ .resource = access.input, .predecessor = inputPass, .successor = access.pass };
                    dependancyData.deps.append(dep) catch std.debug.print("ERROR: 3.DependancyExtractor: Dependancies append failed\n", .{});
                }
            }
            // // register AFTER the consumer check so this access sees the PRIOR writer not itself
            // const isWrite = (bufAccesses.access == .write or bufAccesses.bufOutput != null);
            // if (isWrite) {
            //     const producedKey: u16 = if (bufAccesses.bufOutput) |out| out.val() else inputBufKey;
            //     dependancyData.lastBufWriter.upsert(producedKey, bufAccesses.pass);
            // }
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("3.DependancyExtractor: \n", .{});
            for (dependancyData.deps.constSlice()) |dep| {
                const predName = try registryData.getPassName(dep.predecessor);
                const succName = try registryData.getPassName(dep.successor);
                const resName = switch (dep.resource) {
                    .bufPassId => |id| try registryData.getBufferName(id),
                    .texPassId => |id| try registryData.getTextureName(id),
                };
                std.debug.print("- Dep .( .{s} = {s}, .predecessor = {s}, .successor = {s})\n", .{ @tagName(dep.resource), resName, predName, succName });
            }
            std.debug.print("\n", .{});
        }
    }
};
