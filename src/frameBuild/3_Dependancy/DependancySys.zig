const BufferDependancy = @import("../../frameBuild/components.zig").BufferDependancy;
const TextureDependancy = @import("../../frameBuild/components.zig").TextureDependancy;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const DependancyData = @import("DependancyData.zig").DependancyData;
const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const AccessData = @import("../1.5_Access/AccessData.zig").AccessData;

// Step 3

pub const DependancySys = struct {
    pub fn buildDependencies(dependancyData: *DependancyData, accessData: *const AccessData, registryData: *const RegistryData) !void {
        dependancyData.bufDeps.clear();
        dependancyData.texDeps.clear();
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
            const inputBuf = bufAccesses.input;

            if (dependancyData.lastBufWriter.isKeyUsed(inputBuf) == true) {
                // Graph Edge only if its a cross pass dependancy (Pass does not consume its own resourcve)
                const inputPass = dependancyData.lastBufWriter.getByKey(inputBuf);
                if (inputPass != bufAccesses.pass) {
                    const bufDep = BufferDependancy{ .buf = bufAccesses.input, .predecessor = inputPass, .successor = bufAccesses.pass };
                    dependancyData.bufDeps.append(bufDep) catch std.debug.print("ERROR: 3.DependancyExtractor: bufDependancies append failed\n", .{});
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
            const inputTex = texAccess.input;

            if (dependancyData.lastTexWriter.isKeyUsed(inputTex) == true) {
                // Graph Edge only if its a cross pass dependancy (Pass does not consume its own resourcve)
                const inputPass = dependancyData.lastTexWriter.getByKey(inputTex);
                if (inputPass != texAccess.pass) {
                    const texDep = TextureDependancy{ .tex = texAccess.input, .predecessor = inputPass, .successor = texAccess.pass };
                    dependancyData.texDeps.append(texDep) catch std.debug.print("ERROR: 3.DependancyExtractor: texDependancies append failed\n", .{});
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
            for (dependancyData.bufDeps.constSlice()) |bufDep| {
                const bufName = try registryData.getBufferName(bufDep.buf);
                const predName = try registryData.getPassName(bufDep.predecessor);
                const succName = try registryData.getPassName(bufDep.successor);
                std.debug.print("- BufDep .( .buf = {s}, .predecessor = {s}, .successor = {s})\n", .{ bufName, predName, succName });
            }
            for (dependancyData.texDeps.constSlice()) |texDep| {
                const texName = try registryData.getTextureName(texDep.tex);
                const predName = try registryData.getPassName(texDep.predecessor);
                const succName = try registryData.getPassName(texDep.successor);
                std.debug.print("- TexDep .( .tex = {s}, .predecessor = {s}, .successor = {s})\n", .{ texName, predName, succName });
            }
            std.debug.print("\n", .{});
        }
    }
};
