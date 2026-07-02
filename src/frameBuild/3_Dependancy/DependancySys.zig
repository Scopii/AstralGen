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
            if (bufAccess.bufOutput) |bufOutput| {
                const outputBufKey: u16 = bufOutput.val();
                // Double Write Check: Only allowed exactly one producer!
                if (dependancyData.lastBufWriter.isKeyUsed(outputBufKey)) {
                    const existingWriter = dependancyData.lastBufWriter.getByKey(outputBufKey);
                    const writerPassString = try registryData.getPassName(existingWriter);
                    const passString = try registryData.getPassName(bufAccess.pass);
                    const bufName = try registryData.getBufferName(bufOutput);
                    std.debug.print("VALIDATION: Buffer {s} produced by both {s} and {s}\n", .{ bufName, writerPassString, passString });
                }
                dependancyData.lastBufWriter.upsert(outputBufKey, bufAccess.pass);
            }
        }

        // Resolve Buffer Consumers
        for (accessData.bufAccesses.constSlice()) |bufAccesses| {
            const inputBufKey: u16 = bufAccesses.bufInput.val();

            if (dependancyData.lastBufWriter.isKeyUsed(inputBufKey) == true) {
                // Graph Edge only if its a cross pass dependancy (Pass does not consume its own resourcve)
                const inputPass = dependancyData.lastBufWriter.getByKey(inputBufKey);
                if (inputPass.val() != bufAccesses.pass.val()) {
                    const bufDep = BufferDependancy{ .buf = bufAccesses.bufInput, .predecessor = inputPass, .successor = bufAccesses.pass };
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
            if (texAccess.texOutput) |texOutput| {
                const outputTexKey: u16 = texOutput.val();
                // Double Write Check: Only allowed exactly one producer!
                if (dependancyData.lastTexWriter.isKeyUsed(outputTexKey)) {
                    const existingWriter = dependancyData.lastTexWriter.getByKey(outputTexKey);
                    const writerPassString = try registryData.getPassName(existingWriter);
                    const passString = try registryData.getPassName(texAccess.pass);
                    const texName = try registryData.getTextureName(texOutput);
                    std.debug.print("VALIDATION: Texture {s} produced by both {s} and {s}\n", .{ texName, writerPassString, passString });
                }
                dependancyData.lastTexWriter.upsert(outputTexKey, texAccess.pass);
            }
        }

        // Resolve Texture Consumers
        for (accessData.texAccesses.constSlice()) |texAccess| {
            const inputTexKey: u16 = texAccess.texInput.val();

            if (dependancyData.lastTexWriter.isKeyUsed(inputTexKey) == true) {
                // Graph Edge only if its a cross pass dependancy (Pass does not consume its own resourcve)
                const inputPass = dependancyData.lastTexWriter.getByKey(inputTexKey);
                if (inputPass.val() != texAccess.pass.val()) {
                    const texDep = TextureDependancy{ .tex = texAccess.texInput, .predecessor = inputPass, .successor = texAccess.pass };
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
                const predecessorName = try registryData.getPassName(bufDep.predecessor);
                const successorName = try registryData.getPassName(bufDep.successor);
                std.debug.print("- BufDep .( .buf = {s}, .predecessor = {s}, .successor = {s})\n", .{ bufName, predecessorName, successorName });
            }
            for (dependancyData.texDeps.constSlice()) |texDep| {
                const texName = try registryData.getTextureName(texDep.tex);
                const predecessorName = try registryData.getPassName(texDep.predecessor);
                const successorName = try registryData.getPassName(texDep.successor);
                std.debug.print("- TexDep .( .tex = {s}, .predecessor = {s}, .successor = {s})\n", .{ texName, predecessorName, successorName });
            }
            std.debug.print("\n", .{});
        }
    }
};
