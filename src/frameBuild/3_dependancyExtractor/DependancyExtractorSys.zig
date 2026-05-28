const BufferDependancy = @import("../../frameBuild/components.zig").BufferDependancy;
const TextureDependancy = @import("../../frameBuild/components.zig").TextureDependancy;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const ResourceExtractorData = @import("../2_resourceExtractor/ResourceExtractorData.zig").ResourceExtractorData;
const DependancyExtractorData = @import("DependancyExtractorData.zig").DependancyExtractorData;

// Step 3

pub const DependancyExtractorSys = struct {
    pub fn buildDependencies(dependancyExtractor: *DependancyExtractorData, resourceExtractor: *const ResourceExtractorData) void {
        dependancyExtractor.bufDependancies.clear();
        dependancyExtractor.texDependancies.clear();

        dependancyExtractor.lastBufWriter.clear();
        dependancyExtractor.lastTexWriter.clear();

        // Register Buffer Producers
        for (resourceExtractor.bufAccesses.constSlice()) |bufAccess| {
            if (bufAccess.bufOutput) |bufOutput| {
                const outputBufKey: u16 = @intFromEnum(bufOutput);

                // Double Write Check: Only allowed exactly one producer!
                if (dependancyExtractor.lastBufWriter.isKeyUsed(outputBufKey)) {
                    const existingWriter = dependancyExtractor.lastBufWriter.getByKey(outputBufKey);
                    std.debug.print("VALIDATION: Buffer {s} produced by both {s} and {s}\n", .{ @tagName(bufOutput), @tagName(existingWriter), @tagName(bufAccess.passEnum) });
                }

                dependancyExtractor.lastBufWriter.upsert(outputBufKey, bufAccess.passEnum);
            }
        }

        // Resolve Buffer Consumers
        for (resourceExtractor.bufAccesses.constSlice()) |bufAccesses| {
            const inputBufKey: u16 = @intFromEnum(bufAccesses.bufInput);

            if (dependancyExtractor.lastBufWriter.isKeyUsed(inputBufKey) == true) {
                // Graph Edge only if its a cross pass dependancy (Pass does not consume its own resourcve)
                const inputPass = dependancyExtractor.lastBufWriter.getByKey(inputBufKey);

                if (inputPass != bufAccesses.passEnum) {
                    const bufDep = BufferDependancy{ .bufEnum = bufAccesses.bufInput, .predecessor = inputPass, .successor = bufAccesses.passEnum };
                    dependancyExtractor.bufDependancies.append(bufDep) catch std.debug.print("ERROR: 3.DependancyExtractor: bufDependancies append failed\n", .{});
                }
            }
        }

        // Register Texture Producers
        for (resourceExtractor.texAccesses.constSlice()) |texAccess| {
            if (texAccess.texOutput) |texOutput| {
                const outputTexKey: u16 = @intFromEnum(texOutput);

                // Double Write Check: Only allowed exactly one producer!
                if (dependancyExtractor.lastTexWriter.isKeyUsed(outputTexKey)) {
                    const existingWriter = dependancyExtractor.lastTexWriter.getByKey(outputTexKey);
                    std.debug.print("VALIDATION: Texture {s} produced by both {s} and {s}\n", .{ @tagName(texOutput), @tagName(existingWriter), @tagName(texAccess.passEnum) });
                }

                dependancyExtractor.lastTexWriter.upsert(outputTexKey, texAccess.passEnum);
            }
        }

        // Resolve Texture Consumers
        for (resourceExtractor.texAccesses.constSlice()) |texAccesses| {
            const inputTexKey: u16 = @intFromEnum(texAccesses.texInput);

            if (dependancyExtractor.lastTexWriter.isKeyUsed(inputTexKey) == true) {
                // Graph Edge only if its a cross pass dependancy (Pass does not consume its own resourcve)
                const inputPass = dependancyExtractor.lastTexWriter.getByKey(inputTexKey);

                if (inputPass != texAccesses.passEnum) {
                    const texDep = TextureDependancy{ .texEnum = texAccesses.texInput, .predecessor = inputPass, .successor = texAccesses.passEnum };
                    dependancyExtractor.texDependancies.append(texDep) catch std.debug.print("ERROR: 3.DependancyExtractor: texDependancies append failed\n", .{});
                }
            }
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("3.DependancyExtractor: \n", .{});
            for (dependancyExtractor.bufDependancies.constSlice()) |bufDep| std.debug.print("- BufDep{}\n", .{bufDep});
            for (dependancyExtractor.texDependancies.constSlice()) |texDep| std.debug.print("- TexDep{}\n", .{texDep});
            std.debug.print("\n", .{});
        }
    }
};
