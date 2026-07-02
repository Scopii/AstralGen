const BufferDependancy = @import("../../frameBuild/components.zig").BufferDependancy;
const TextureDependancy = @import("../../frameBuild/components.zig").TextureDependancy;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const ResourceExtractorData = @import("../2_resourceExtractor/ResourceExtractorData.zig").ResourceExtractorData;
const PassExtractorData = @import("../1_passExtractor/PassExtractorData.zig").PassExtractorData;
const DependancyExtractorData = @import("DependancyExtractorData.zig").DependancyExtractorData;
const ResourceRegistryData = @import("../0_resourceRegistry/ResourceRegistryData.zig").ResourceRegistryData;
const AccessExtractorData = @import("../1.5_accessExtractor/AccessExtractorData.zig").AccessExtractorData;

// Step 3

pub const DependancyExtractorSys = struct {
    pub fn buildDependencies(dependancyExtractor: *DependancyExtractorData, accessExtractor: *const AccessExtractorData, resourceRegistry: *const ResourceRegistryData) !void {
        dependancyExtractor.bufDependancies.clear();
        dependancyExtractor.texDependancies.clear();

        dependancyExtractor.lastBufWriter.clear();
        dependancyExtractor.lastTexWriter.clear();

        // Register Buffer Producers
        for (accessExtractor.bufAccesses.constSlice()) |bufAccess| {
            if (bufAccess.bufOutput) |bufOutput| {
                const outputBufKey: u16 = bufOutput.val();

                // Double Write Check: Only allowed exactly one producer!
                if (dependancyExtractor.lastBufWriter.isKeyUsed(outputBufKey)) {
                    const existingWriter = dependancyExtractor.lastBufWriter.getByKey(outputBufKey);
                    const writerPassString = try resourceRegistry.getPassName(existingWriter);
                    const passString = try resourceRegistry.getPassName(bufAccess.pass);
                    const bufName = try resourceRegistry.getBufferName(bufOutput);
                    std.debug.print("VALIDATION: Buffer {s} produced by both {s} and {s}\n", .{ bufName, writerPassString, passString });
                }

                dependancyExtractor.lastBufWriter.upsert(outputBufKey, bufAccess.pass);
            }
        }

        // Resolve Buffer Consumers
        for (accessExtractor.bufAccesses.constSlice()) |bufAccesses| {
            const inputBufKey: u16 = bufAccesses.bufInput.val();

            if (dependancyExtractor.lastBufWriter.isKeyUsed(inputBufKey) == true) {
                // Graph Edge only if its a cross pass dependancy (Pass does not consume its own resourcve)
                const inputPass = dependancyExtractor.lastBufWriter.getByKey(inputBufKey);

                if (inputPass.val() != bufAccesses.pass.val()) {
                    const bufDep = BufferDependancy{ .buf = bufAccesses.bufInput, .predecessor = inputPass, .successor = bufAccesses.pass };
                    dependancyExtractor.bufDependancies.append(bufDep) catch std.debug.print("ERROR: 3.DependancyExtractor: bufDependancies append failed\n", .{});
                }
            }

            // register AFTER the consumer check so this access sees the PRIOR writer not itself
            const isWrite = (bufAccesses.access == .write or bufAccesses.bufOutput != null);
            if (isWrite) {
                const producedKey: u16 = if (bufAccesses.bufOutput) |out| out.val() else inputBufKey;
                dependancyExtractor.lastBufWriter.upsert(producedKey, bufAccesses.pass);
            }
        }

        // Register Texture Producers
        for (accessExtractor.texAccesses.constSlice()) |texAccess| {
            if (texAccess.texOutput) |texOutput| {
                const outputTexKey: u16 = texOutput.val();

                // Double Write Check: Only allowed exactly one producer!
                if (dependancyExtractor.lastTexWriter.isKeyUsed(outputTexKey)) {
                    const existingWriter = dependancyExtractor.lastTexWriter.getByKey(outputTexKey);
                    const writerPassString = try resourceRegistry.getPassName(existingWriter);
                    const passString = try resourceRegistry.getPassName(texAccess.pass);
                    const texName = try resourceRegistry.getTextureName(texOutput);
                    std.debug.print("VALIDATION: Texture {s} produced by both {s} and {s}\n", .{ texName, writerPassString, passString });
                }

                dependancyExtractor.lastTexWriter.upsert(outputTexKey, texAccess.pass);
            }
        }

        // Resolve Texture Consumers
        for (accessExtractor.texAccesses.constSlice()) |texAccess| {
            const inputTexKey: u16 = texAccess.texInput.val();

            if (dependancyExtractor.lastTexWriter.isKeyUsed(inputTexKey) == true) {
                // Graph Edge only if its a cross pass dependancy (Pass does not consume its own resourcve)
                const inputPass = dependancyExtractor.lastTexWriter.getByKey(inputTexKey);

                if (inputPass.val() != texAccess.pass.val()) {
                    const texDep = TextureDependancy{ .tex = texAccess.texInput, .predecessor = inputPass, .successor = texAccess.pass };
                    dependancyExtractor.texDependancies.append(texDep) catch std.debug.print("ERROR: 3.DependancyExtractor: texDependancies append failed\n", .{});
                }
            }

            // register AFTER the consumer check so this access sees the PRIOR writer not itself
            const isWrite = (texAccess.access == .write or texAccess.texOutput != null);
            if (isWrite) {
                const producedKey: u16 = if (texAccess.texOutput) |out| out.val() else inputTexKey;
                dependancyExtractor.lastTexWriter.upsert(producedKey, texAccess.pass);
            }
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("3.DependancyExtractor: \n", .{});
            for (dependancyExtractor.bufDependancies.constSlice()) |bufDep| {
                const bufName = try resourceRegistry.getBufferName(bufDep.buf);
                const predecessorName = try resourceRegistry.getPassName(bufDep.predecessor);
                const successorName = try resourceRegistry.getPassName(bufDep.successor);
                std.debug.print("- BufDep .( .buf = {s}, .predecessor = {s}, .successor = {s})\n", .{ bufName, predecessorName, successorName });
            }
            for (dependancyExtractor.texDependancies.constSlice()) |texDep| {
                const texName = try resourceRegistry.getTextureName(texDep.tex);
                const predecessorName = try resourceRegistry.getPassName(texDep.predecessor);
                const successorName = try resourceRegistry.getPassName(texDep.successor);
                std.debug.print("- TexDep .( .tex = {s}, .predecessor = {s}, .successor = {s})\n", .{ texName, predecessorName, successorName });
            }
            std.debug.print("\n", .{});
        }
    }
};
