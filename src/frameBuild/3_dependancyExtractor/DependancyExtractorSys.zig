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

        // For Buffers
        const bufAccesses = resourceExtractor.bufAccesses.constSlice();

        for (0..bufAccesses.len) |firstIndex| {
            const firstAccess = bufAccesses[firstIndex];

            if (firstAccess.bufOutput) |firstBufOutput| {
                for (0..bufAccesses.len) |secondIndex| {
                    if (firstIndex != secondIndex) {
                        const secondAccess = bufAccesses[secondIndex];

                        if (firstBufOutput == secondAccess.bufInput) {
                            const bufDependancy = BufferDependancy{
                                .bufEnum = firstBufOutput,
                                .predecessor = firstAccess.passEnum,
                                .successor = secondAccess.passEnum,
                            };
                            dependancyExtractor.bufDependancies.append(bufDependancy) catch std.debug.print("ERROR: Dependancy Extractor bufDependancy append failed!\n", .{});
                        }
                    }
                }
            }
        }

        // For Textures
        const texAccesses = resourceExtractor.texAccesses.constSlice();

        for (0..texAccesses.len) |firstIndex| {
            const firstAccess = texAccesses[firstIndex];

            if (firstAccess.texOutput) |firstTexOutput| {
                for (0..texAccesses.len) |secondIndex| {
                    if (firstIndex != secondIndex) {
                        const secondAccess = texAccesses[secondIndex];

                        if (firstTexOutput == secondAccess.texInput) {
                            const texDependancy = TextureDependancy{
                                .texEnum = firstTexOutput,
                                .predecessor = firstAccess.passEnum,
                                .successor = secondAccess.passEnum,
                            };
                            dependancyExtractor.texDependancies.append(texDependancy) catch std.debug.print("ERROR: Dependancy Extractor bufDependancy append failed!\n", .{});
                        }
                    }
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
