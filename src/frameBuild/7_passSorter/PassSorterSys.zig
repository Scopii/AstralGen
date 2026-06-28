const TaskOrMeshIndirectExec = @import("../../render/types/pass/PassInstance.zig").TaskOrMeshIndirectExec;
const ComputeIndirectExec = @import("../../render/types/pass/PassInstance.zig").ComputeIndirectExec;
const VertexBufferFill = @import("../../render/types/pass/VertexBufferFill.zig").VertexBufferFill;
const IndexBufferFill = @import("../../render/types/pass/IndexBufferFill.zig").IndexBufferFill;
const VertexAttribute = @import("../../render/types/pass/VertexAttribute.zig").VertexAttribute;
const AttachmentFill = @import("../../render/types/pass/AttachmentFill.zig").AttachmentFill;
const PassInstance = @import("../../render/types/pass/PassInstance.zig").PassInstance;
const TextureFill = @import("../../render/types/pass/TextureFill.zig").TextureFill;
const BufferFill = @import("../../render/types/pass/BufferFill.zig").BufferFill;
const PassId = @import("../../.configs/idConfig.zig").PassId;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const ResourceRegistryData = @import("../0_resourceRegistry/ResourceRegistryData.zig").ResourceRegistryData;
const PassExtractorData = @import("../1_passExtractor/PassExtractorData.zig").PassExtractorData;
const GraphOptimizerData = @import("../4.5_graphOptimizer/GraphOptimizerData.zig").GraphOptimizerData;
const GroupMergerData = @import("../5.4_groupMerger/GroupMergerData.zig").GroupMergerData;
const ResourceAssignerData = @import("../6_resourceAssigner/ResourceAssignerData.zig").ResourceAssignerData;
const PassSorterData = @import("../7_passSorter/PassSorterData.zig").PassSorterData;

// Step 7

pub const PassSorterSys = struct {
    pub fn buildFrame(
        passSorter: *PassSorterData,
        passExtractor: *const PassExtractorData,
        graphOptimizer: *const GraphOptimizerData,
        groupMerger: *const GroupMergerData,
        resourceAssigner: *const ResourceAssignerData,
        resourceRegistry: *const ResourceRegistryData,
    ) !void {
        passSorter.sortedRenderNodes.clear();

        const composites = passExtractor.composites.constSlice();
        const blits = passExtractor.blits.constSlice();

        // Check Buckets for Correct Pass
        for (graphOptimizer.optimizedGraph.getConstItems()) |graphNode| {
            const passId = graphNode.pass;

            var neededClears = false;
            // Buffer Clears
            for (groupMerger.bufClears.constSlice()) |bufClear| {
                if (bufClear.passAfterClear.val() == passId.val()) {
                    // LOOKUP FOR bufClear.Index to ENUM!
                    const bufId = resourceAssigner.usedTransientBufs.buffer[bufClear.sharedBufIndex].hardwareBuf;
                    try passSorter.sortedRenderNodes.append(.{ .clearBuffer = bufId });
                    neededClears = true;
                }
            }
            // Texture Clears
            for (groupMerger.texClears.constSlice()) |texClear| {
                if (texClear.passAfterClear.val() == passId.val()) {
                    // LOOKUP FOR texClear.Index to ENUM!
                    const texId = resourceAssigner.usedTransientTexes.buffer[texClear.sharedTexIndex].hardwareTex;
                    try passSorter.sortedRenderNodes.append(.{ .clearTexture = texId });
                    neededClears = true;
                }
            }
            // Call for Clear Barrier baking if needed
            if (neededClears) try passSorter.sortedRenderNodes.append(.barrierBakeClears);

            // Passes
            const renderSize = passExtractor.passResolutions.getByKey(passId.val());
            const passInstance = try fillPassHardwareIds(passId, resourceAssigner, resourceRegistry);

            passSorter.sortedRenderNodes.append(.{ .passNode = .{ .pass = passInstance, .passWidth = renderSize.width, .passHeight = renderSize.height } }) catch {
                std.debug.print("7.PassSorter: Pass Append to sortedRenderNodes failed", .{});
            };

            // Blits
            for (blits) |blit| {
                if (blit.pass.val() == passId.val()) {
                    var blitCopy = blit;

                    switch (blit.srcTexUnion) {
                        .texName => |name| {
                            const texPassId = try resourceRegistry.getTexturePassId(name);
                            const hardwareTexId = resourceAssigner.texAssigns.getByKey(texPassId.val());
                            blitCopy.srcTexUnion = .{ .texId = hardwareTexId };
                        },
                        .texPassId => |texPassId| {
                            const hardwareTexId = resourceAssigner.texAssigns.getByKey(texPassId.val());
                            blitCopy.srcTexUnion = .{ .texId = hardwareTexId };
                        },
                        .texId => {},
                    }
                    passSorter.sortedRenderNodes.append(.{ .viewportBlit = blitCopy }) catch std.debug.print("7.PassSorter: Blit Append to sortedRenderNodes failed", .{});
                }
            }

            // Composites
            for (composites) |composite| {
                if (composite.pass.val() == passId.val()) {
                    var compositeCopy = composite;

                    switch (compositeCopy.srcTexUnion) {
                        .texName => |name| {
                            const texPassId = try resourceRegistry.getTexturePassId(name);
                            const hardwareTexId = resourceAssigner.texAssigns.getByKey(texPassId.val());
                            compositeCopy.srcTexUnion = .{ .texId = hardwareTexId };
                        },
                        .texPassId => |texPassId| {
                            const hardwareTexId = resourceAssigner.texAssigns.getByKey(texPassId.val());
                            compositeCopy.srcTexUnion = .{ .texId = hardwareTexId };
                        },
                        .texId => {},
                    }
                    passSorter.sortedRenderNodes.append(.{ .compositeNode = compositeCopy }) catch std.debug.print("7.PassSorter: Composite Append to sortedRenderNodes failed", .{});
                }
            }
        }

        // Debug Prints
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("7.PassSorter:\n", .{});
            for (passSorter.sortedRenderNodes.constSlice(), 0..) |*renderNode, index| {
                switch (renderNode.*) {
                    .passNode => |*passNode| std.debug.print("- {}. Pass: {s}\n", .{ index, passNode.pass.getName() }),
                    .compositeNode => |*composite| std.debug.print("- {}. Composite: {s} (Pass {s})\n", .{ index, composite.name, try resourceRegistry.getPassName(composite.pass) }),
                    .viewportBlit => |*blit| std.debug.print("- {}. Blit: {s} (Pass {s})\n", .{ index, blit.name, try resourceRegistry.getPassName(blit.pass) }),
                    .uiNode => |*ui| std.debug.print("- {}. UI: {s} (WindowID {})\n", .{ index, ui.name, ui.windowId }),
                    .clearBuffer => |*clearBuf| std.debug.print("- {}. ClearBuffer: {}\n", .{ index, clearBuf.* }),
                    .clearTexture => |*clearTex| std.debug.print("- {}. ClearTexture: {}\n", .{ index, clearTex.* }),
                    .barrierBakeClears => std.debug.print("- {}. Bake Clears\n", .{index}),
                }
            }
            std.debug.print("\n", .{});
        }
    }
};

fn fillPassHardwareIds(passId: PassId, resourceAssigner: *const ResourceAssignerData, resourceRegistry: *const ResourceRegistryData) !PassInstance {
    const passName = try resourceRegistry.getPassName(passId);
    const passDef = try resourceRegistry.getPassDefinition(passName);

    const mainOutputTexId = if (passDef.outputTex) |output| try resourceRegistry.getTexturePassId(output) else null;

    var filledPass = PassInstance{
        .name = undefined,
        .execution = undefined,
        .mainOutputTex = if (mainOutputTexId) |outputId| resourceAssigner.texAssigns.getByKey(outputId.val()) else null,
    };

    filledPass.name.fill(passDef.name.get());

    for (passDef.passAttribute.constSlice()) |attribute| {
        switch (attribute) {
            .execution => |exec| {
                switch (exec) {
                    .computeIndirect => |compIndirect| {
                        const bufPassId = try resourceRegistry.getBufferPassId(compIndirect.indirectBuf);
                        const hardwareBufId = resourceAssigner.bufAssigns.getByKey(bufPassId.val());

                        const compIndirectExec = ComputeIndirectExec{
                            .indirectBuf = hardwareBufId,
                            .indirectBufOffset = compIndirect.indirectBufOffset,
                        };
                        filledPass.execution = .{ .computeIndirect = compIndirectExec };
                    },
                    .taskOrMeshIndirect => |taskOrMeshIndirect| {
                        const bufPassId = try resourceRegistry.getBufferPassId(taskOrMeshIndirect.indirectBuf);
                        const hardwareBufId = resourceAssigner.bufAssigns.getByKey(bufPassId.val());

                        const taskMeshIndirectExec = TaskOrMeshIndirectExec{
                            .groupX = taskOrMeshIndirect.groupX,
                            .groupY = taskOrMeshIndirect.groupY,
                            .groupZ = taskOrMeshIndirect.groupZ,
                            .indirectBuf = hardwareBufId,
                            .indirectBufOffset = taskOrMeshIndirect.indirectBufOffset,
                        };
                        filledPass.execution = .{ .taskOrMeshIndirect = taskMeshIndirectExec };
                    },
                    .compute => |comp| {
                        filledPass.execution = .{ .compute = comp };
                    },
                    .taskOrMesh => |taskOrMesh| {
                        filledPass.execution = .{ .taskOrMesh = taskOrMesh };
                    },
                    .graphics => |graphics| {
                        filledPass.execution = .{ .graphics = graphics };
                    },
                    // inline else => |val, tag| @field(filledPass.execution, @tagName(tag)) = val,
                }
            },
            .shaderInf => |shaderInf| {
                filledPass.shaderIds.appendAssumeCapacity(shaderInf.id);
            },
            .bufSlot => |bufSlot| {
                const bufPassId = try resourceRegistry.getBufferPassId(bufSlot.bufLink.in);
                const hardwareBufId = resourceAssigner.bufAssigns.getByKey(bufPassId.val());

                const bufUse = BufferFill{
                    .bufId = hardwareBufId,
                    .stage = bufSlot.stage,
                    .access = bufSlot.access,
                    .shaderSlot = bufSlot.shaderSlot,
                };
                filledPass.bufUses.appendAssumeCapacity(bufUse);
            },
            .texSlot => |texSlot| {
                const texPassId = try resourceRegistry.getTexturePassId(texSlot.texLink.in);
                const hardwareTexId = resourceAssigner.texAssigns.getByKey(texPassId.val());

                const texUse = TextureFill{
                    .texId = hardwareTexId,
                    .stage = texSlot.stage,
                    .access = texSlot.access,
                    .layout = texSlot.layout,
                    .descUse = texSlot.descUse,
                    .shaderSlot = texSlot.shaderSlot,
                };
                filledPass.texUses.appendAssumeCapacity(texUse);
            },

            .colorAtt => |attSlot| {
                const texPassId = try resourceRegistry.getTexturePassId(attSlot.texLink.in);
                const hardwareTexId = resourceAssigner.texAssigns.getByKey(texPassId.val());

                const colorAttUse = AttachmentFill{
                    .texId = hardwareTexId,
                    .stage = attSlot.stage,
                    .access = attSlot.access,
                    .layout = attSlot.layout,
                    .clear = if (attSlot.clear) |clear| clear else null,
                };
                filledPass.colorAtts.appendAssumeCapacity(colorAttUse);
            },
            .depthAtt => |depthSlot| {
                const texPassId = try resourceRegistry.getTexturePassId(depthSlot.texLink.in);
                const hardwareTexId = resourceAssigner.texAssigns.getByKey(texPassId.val());

                const depthAttUse = AttachmentFill{
                    .texId = hardwareTexId,
                    .stage = depthSlot.stage,
                    .access = depthSlot.access,
                    .layout = depthSlot.layout,
                    .clear = depthSlot.clear,
                };
                filledPass.depthAtt = depthAttUse;
            },
            .stencilAtt => |stencilSlot| {
                const texPassId = try resourceRegistry.getTexturePassId(stencilSlot.texLink.in);
                const hardwareTexId = resourceAssigner.texAssigns.getByKey(texPassId.val());

                filledPass.stencilAtt = AttachmentFill{
                    .texId = hardwareTexId,
                    .stage = stencilSlot.stage,
                    .access = stencilSlot.access,
                    .layout = stencilSlot.layout,
                    .clear = stencilSlot.clear,
                };
            },

            .vertexBuffer => |vertexBufSlot| {
                const texPassId = try resourceRegistry.getBufferPassId(vertexBufSlot.bufInput);
                const hardwareTexId = resourceAssigner.bufAssigns.getByKey(texPassId.val());

                const vertBufUse = VertexBufferFill{
                    .bufId = hardwareTexId,
                    .binding = vertexBufSlot.binding,
                    .stride = vertexBufSlot.stride,
                    .inputRate = vertexBufSlot.inputRate,
                };
                filledPass.vertexBuffers.appendAssumeCapacity(vertBufUse);
            },
            .indexBuffer => |indexBufSlot| {
                const texPassId = try resourceRegistry.getBufferPassId(indexBufSlot.bufInput);
                const hardwareTexId = resourceAssigner.bufAssigns.getByKey(texPassId.val());

                filledPass.indexBuffer = IndexBufferFill{
                    .bufId = hardwareTexId,
                    .indexType = indexBufSlot.indexType,
                };
            },
            .vertexAttribute => |vertAttrib| {
                filledPass.vertexAttributes.appendAssumeCapacity(vertAttrib);
            },
            .renderState => |stateChange| switch (stateChange) {
                inline else => |val, tag| @field(filledPass.renderState, @tagName(tag)) = val,
            },
        }
    }

    return filledPass;
}
