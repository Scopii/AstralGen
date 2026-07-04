const Dependancy = @import("../../frameBuild/components.zig").Dependancy;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const DependancyData = @import("DependancyData.zig").DependancyData;
const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const AccessData = @import("../1.5_Access/AccessData.zig").AccessData;

// Step 3

pub const DependancySys = struct {
    pub fn buildDependencies(dependancyData: *DependancyData, accessData: *const AccessData, registryData: *const RegistryData) !void {
        dependancyData.deps.clear();
        dependancyData.lastBufWriter.clear();
        dependancyData.lastTexWriter.clear();

        // Register Buffer Producers
        for (accessData.bufAccesses.constSlice()) |bufAccess| {
            if (bufAccess.output) |bufOutput| {
                // Double Write Check: Only allowed exactly one producer!
                if (dependancyData.lastBufWriter.isKeyUsed(bufOutput)) {
                    const prevWriter = dependancyData.lastBufWriter.getByKey(bufOutput);
                    const prevName = try registryData.getPassName(prevWriter);
                    const newName = try registryData.getPassName(bufAccess.pass);
                    const bufName = try registryData.getBufferName(bufOutput);
                    std.debug.print("VALIDATION: Buffer {s} produced by both {s} and {s}\n", .{ bufName, prevName, newName });
                }
                dependancyData.lastBufWriter.upsert(bufOutput, bufAccess.pass);
            }
        }

        // Resolve Buffer Consumers
        for (accessData.bufAccesses.constSlice()) |bufAccesses| {
            if (dependancyData.lastBufWriter.isKeyUsed(bufAccesses.input) == true) {
                // Graph Edge only if its a cross pass dependancy (Pass does not consume its own resourcve)
                const inputPass = dependancyData.lastBufWriter.getByKey(bufAccesses.input);
                if (inputPass != bufAccesses.pass) {
                    const bufDep = Dependancy{ .resource = .{ .bufPassId = bufAccesses.input }, .predecessor = inputPass, .successor = bufAccesses.pass };
                    dependancyData.deps.append(bufDep) catch std.debug.print("ERROR: 3.DependancyExtractor: bufDependancies append failed\n", .{});
                }
            }

            // // register AFTER the consumer check so this access sees the PRIOR writer not itself
            // const isWrite = (bufAccesses.access == .write or bufAccesses.bufOutput != null);
            // if (isWrite) {
            //     const producedKey: u16 = if (bufAccesses.bufOutput) |out| out.val() else inputBufKey;
            //     dependancyData.lastBufWriter.upsert(producedKey, bufAccesses.pass);
            // }
        }

        // Register Texture Producers
        for (accessData.texAccesses.constSlice()) |texAccess| {
            if (texAccess.output) |texOutput| {
                // Double Write Check: Only allowed exactly one producer!
                if (dependancyData.lastTexWriter.isKeyUsed(texOutput)) {
                    const prevWriter = dependancyData.lastTexWriter.getByKey(texOutput);
                    const prevName = try registryData.getPassName(prevWriter);
                    const newName = try registryData.getPassName(texAccess.pass);
                    const texName = try registryData.getTextureName(texOutput);
                    std.debug.print("VALIDATION: Texture {s} produced by both {s} and {s}\n", .{ texName, prevName, newName });
                }
                dependancyData.lastTexWriter.upsert(texOutput, texAccess.pass);
            }
        }

        // Resolve Texture Consumers
        for (accessData.texAccesses.constSlice()) |texAccess| {
            if (dependancyData.lastTexWriter.isKeyUsed(texAccess.input) == true) {
                // Graph Edge only if its a cross pass dependancy (Pass does not consume its own resourcve)
                const inputPass = dependancyData.lastTexWriter.getByKey(texAccess.input);
                if (inputPass != texAccess.pass) {
                    const texDep = Dependancy{ .resource = .{ .texPassId = texAccess.input }, .predecessor = inputPass, .successor = texAccess.pass };
                    dependancyData.deps.append(texDep) catch std.debug.print("ERROR: 3.DependancyExtractor: texDependancies append failed\n", .{});
                }
            }

            // // register AFTER the consumer check so this access sees the PRIOR writer not itself
            // const isWrite = (texAccess.access == .write or texAccess.texOutput != null);
            // if (isWrite) {
            //     const producedKey: u16 = if (texAccess.texOutput) |out| out.val() else inputTexKey;
            //     dependancyData.lastTexWriter.upsert(producedKey, texAccess.pass);
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
