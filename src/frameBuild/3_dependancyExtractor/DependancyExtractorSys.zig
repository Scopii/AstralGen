const BufferDependancy = @import("../../frameBuild/components.zig").BufferDependancy;
const TextureDependancy = @import("../../frameBuild/components.zig").TextureDependancy;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const ResourceExtractorData = @import("../2_resourceExtractor/ResourceExtractorData.zig").ResourceExtractorData;
const PassExtractorData = @import("../1_passExtractor/PassExtractorData.zig").PassExtractorData;
const DependancyExtractorData = @import("DependancyExtractorData.zig").DependancyExtractorData;
const ResourceRegistryData = @import("../0_resourceRegistry/ResourceRegistryData.zig").ResourceRegistryData;

// Step 3

pub const DependancyExtractorSys = struct {
    pub fn buildDependencies(
        dependancyExtractor: *DependancyExtractorData,
        resourceExtractor: *const ResourceExtractorData,
        passExtractor: *const PassExtractorData,
        resourceRegistry: *const ResourceRegistryData,
    ) !void {
        dependancyExtractor.bufDependancies.clear();
        dependancyExtractor.texDependancies.clear();

        dependancyExtractor.lastBufWriter.clear();
        dependancyExtractor.lastTexWriter.clear();

        // Register Buffer Producers
        for (resourceExtractor.bufAccesses.constSlice()) |bufAccess| {
            if (bufAccess.bufOutput) |bufOutput| {
                const outputBufKey: u16 = bufOutput.val();

                // Double Write Check: Only allowed exactly one producer!
                if (dependancyExtractor.lastBufWriter.isKeyUsed(outputBufKey)) {
                    const existingWriter = dependancyExtractor.lastBufWriter.getByKey(outputBufKey);
                    const writerPassString = passExtractor.passStrings.getByIndex(existingWriter.val());
                    const passString = passExtractor.passStrings.getByIndex(bufAccess.pass.val());
                    const bufName = try resourceRegistry.getBufferName(bufOutput);
                    std.debug.print("VALIDATION: Buffer {s} produced by both {s} and {s}\n", .{ bufName, writerPassString, passString });
                }

                dependancyExtractor.lastBufWriter.upsert(outputBufKey, bufAccess.pass);
            }
        }

        // Resolve Buffer Consumers
        for (resourceExtractor.bufAccesses.constSlice()) |bufAccesses| {
            const inputBufKey: u16 = bufAccesses.bufInput.val();

            if (dependancyExtractor.lastBufWriter.isKeyUsed(inputBufKey) == true) {
                // Graph Edge only if its a cross pass dependancy (Pass does not consume its own resourcve)
                const inputPass = dependancyExtractor.lastBufWriter.getByKey(inputBufKey);

                if (inputPass.val() != bufAccesses.pass.val()) {
                    const bufDep = BufferDependancy{ .buf = bufAccesses.bufInput, .predecessor = inputPass, .successor = bufAccesses.pass };
                    dependancyExtractor.bufDependancies.append(bufDep) catch std.debug.print("ERROR: 3.DependancyExtractor: bufDependancies append failed\n", .{});
                }
            }
        }

        // Register Texture Producers
        for (resourceExtractor.texAccesses.constSlice()) |texAccess| {
            if (texAccess.texOutput) |texOutput| {
                const outputTexKey: u16 = texOutput.val();

                // Double Write Check: Only allowed exactly one producer!
                if (dependancyExtractor.lastTexWriter.isKeyUsed(outputTexKey)) {
                    const existingWriter = dependancyExtractor.lastTexWriter.getByKey(outputTexKey);
                    const writerPassString = passExtractor.passStrings.getByIndex(existingWriter.val());
                    const passString = passExtractor.passStrings.getByIndex(texAccess.pass.val());
                    const texName = try resourceRegistry.getTextureName(texOutput);
                    std.debug.print("VALIDATION: Texture {s} produced by both {s} and {s}\n", .{ texName, writerPassString, passString });
                }

                dependancyExtractor.lastTexWriter.upsert(outputTexKey, texAccess.pass);
            }
        }

        // Resolve Texture Consumers
        for (resourceExtractor.texAccesses.constSlice()) |texAccesses| {
            const inputTexKey: u16 = texAccesses.texInput.val();

            if (dependancyExtractor.lastTexWriter.isKeyUsed(inputTexKey) == true) {
                // Graph Edge only if its a cross pass dependancy (Pass does not consume its own resourcve)
                const inputPass = dependancyExtractor.lastTexWriter.getByKey(inputTexKey);

                if (inputPass.val() != texAccesses.pass.val()) {
                    const texDep = TextureDependancy{ .tex = texAccesses.texInput, .predecessor = inputPass, .successor = texAccesses.pass };
                    dependancyExtractor.texDependancies.append(texDep) catch std.debug.print("ERROR: 3.DependancyExtractor: texDependancies append failed\n", .{});
                }
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
