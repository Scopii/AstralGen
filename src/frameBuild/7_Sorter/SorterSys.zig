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

const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const PassData = @import("../1_Pass/PassData.zig").PassData;
const OptimizerData = @import("../4.5_Optimizer/OptimizerData.zig").OptimizerData;
const GroupData = @import("../5.4_Group/GroupData.zig").GroupData;
const AssignerData = @import("../6_Assigner/AssignerData.zig").AssignerData;
const SorterData = @import("../7_Sorter/SorterData.zig").SorterData;

// Step 7

pub const SorterSys = struct {
    pub fn build(
        sorterData: *SorterData,
        passData: *const PassData,
        optimizerData: *const OptimizerData,
        groupData: *const GroupData,
        assignerData: *const AssignerData,
        registryData: *const RegistryData,
    ) !void {
        sorterData.sortedNodes.clear();

        // Check Buckets for Correct Pass
        for (optimizerData.optimizedGraph.getConstItems()) |graphNode| {
            const passId = graphNode.pass;

            var neededClears = false;
            // Resource Clears
            for (groupData.bufClears.constSlice()) |bufClear| {
                if (bufClear.passAfterClear == passId) {
                    try sorterData.sortedNodes.append(.{ .clearBuffer = assignerData.usedTransientBufs.buffer[bufClear.sharedIndex].hardwareBuf });
                    neededClears = true;
                }
            }
            for (groupData.texClears.constSlice()) |texClear| {
                if (texClear.passAfterClear == passId) {
                    try sorterData.sortedNodes.append(.{ .clearTexture = assignerData.usedTransientTexes.buffer[texClear.sharedIndex].hardwareTex });
                    neededClears = true;
                }
            }
            // Call for Clear Barrier baking if needed
            if (neededClears) try sorterData.sortedNodes.append(.barrierBakeClears);

            // Passes
            const passInstance = try fillPassHardwareIds(passId, assignerData, registryData);
            sorterData.sortedNodes.append(.{ .passNode = passInstance }) catch std.debug.print("7.PassSorter: Pass Append to sortedRenderNodes failed", .{});

            // Blits
            for (passData.blits.constSlice()) |blit| {
                if (blit.pass == passId) {
                    var blitCopy = blit;

                    switch (blit.srcTexUnion) {
                        .texName => |name| {
                            const texPassId = try registryData.getTexturePassId(name);
                            const hardwareTexId = assignerData.texAssigns.getByKey(texPassId);
                            blitCopy.srcTexUnion = .{ .texId = hardwareTexId };
                        },
                        .texPassId => |texPassId| {
                            const hardwareTexId = assignerData.texAssigns.getByKey(texPassId);
                            blitCopy.srcTexUnion = .{ .texId = hardwareTexId };
                        },
                        .texId => {},
                    }
                    sorterData.sortedNodes.append(.{ .blitNode = blitCopy }) catch std.debug.print("7.PassSorter: Blit Append to sortedRenderNodes failed", .{});
                }
            }

            // Composites
            for (passData.composites.constSlice()) |composite| {
                if (composite.pass == passId) {
                    var compositeCopy = composite;

                    switch (compositeCopy.srcTexUnion) {
                        .texName => |name| {
                            const texPassId = try registryData.getTexturePassId(name);
                            const hardwareTexId = assignerData.texAssigns.getByKey(texPassId);
                            compositeCopy.srcTexUnion = .{ .texId = hardwareTexId };
                        },
                        .texPassId => |texPassId| {
                            const hardwareTexId = assignerData.texAssigns.getByKey(texPassId);
                            compositeCopy.srcTexUnion = .{ .texId = hardwareTexId };
                        },
                        .texId => {},
                    }
                    sorterData.sortedNodes.append(.{ .compositeNode = compositeCopy }) catch std.debug.print("7.PassSorter: Composite Append to sortedRenderNodes failed", .{});
                }
            }
        }

        // Debug Prints
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("7.PassSorter:\n", .{});
            for (sorterData.sortedNodes.constSlice(), 0..) |*renderNode, index| {
                switch (renderNode.*) {
                    .passNode => |*passNode| std.debug.print("- {}. Pass: {s}\n", .{ index, passNode.getName() }),
                    .compositeNode => |*composite| std.debug.print("- {}. Composite: {s} (Pass {s})\n", .{ index, composite.name, try registryData.getPassName(composite.pass) }),
                    .blitNode => |*blit| std.debug.print("- {}. Blit: {s} (Pass {s})\n", .{ index, blit.name, try registryData.getPassName(blit.pass) }),
                    .uiNode => |*ui| std.debug.print("- {}. UI: {s} (WindowID {})\n", .{ index, ui.name, ui.windowId }),
                    .clearBuffer => |*clearBuf| std.debug.print("- {}. ClearBuffer: BufId {}\n", .{ index, clearBuf.val() }),
                    .clearTexture => |*clearTex| std.debug.print("- {}. ClearTexture: TexId {}\n", .{ index, clearTex.val() }),
                    .barrierBakeClears => std.debug.print("- {}. Bake Clears\n", .{index}),
                }
            }
            std.debug.print("\n", .{});
        }
    }
};

fn fillPassHardwareIds(passId: PassId, assignerData: *const AssignerData, registryData: *const RegistryData) !PassInstance {
    const passName = try registryData.getPassName(passId);
    const passDef = try registryData.getPassDefinition(passName);
    const mainOutputTexId = if (passDef.outputTex) |output| try registryData.getTexturePassId(output) else null;

    var filledPass = PassInstance{
        .name = undefined,
        .execution = undefined,
        .mainOutputTex = if (mainOutputTexId) |outputId| assignerData.texAssigns.getByKey(outputId) else null,
    };

    filledPass.name.fill(passDef.name.get());

    for (passDef.passAttribute.constSlice()) |attribute| {
        switch (attribute) {
            .execution => |exec| {
                switch (exec) {
                    .compute => |comp| {
                        filledPass.execution = .{ .compute = comp };
                    },
                    .taskOrMesh => |taskOrMesh| {
                        filledPass.execution = .{ .taskOrMesh = taskOrMesh };
                    },
                    .graphics => |graphics| {
                        filledPass.execution = .{ .graphics = graphics };
                    },
                    .computeIndirect => |compIndirect| {
                        const bufPassId = try registryData.getBufferPassId(compIndirect.indirectBuf);
                        const compIndirectExec = ComputeIndirectExec{
                            .indirectBuf = assignerData.bufAssigns.getByKey(bufPassId),
                            .indirectBufOffset = compIndirect.indirectBufOffset,
                        };
                        filledPass.execution = .{ .computeIndirect = compIndirectExec };
                    },
                    .taskOrMeshIndirect => |taskOrMeshIndirect| {
                        const bufPassId = try registryData.getBufferPassId(taskOrMeshIndirect.indirectBuf);
                        const taskMeshIndirectExec = TaskOrMeshIndirectExec{
                            .groupX = taskOrMeshIndirect.groupX,
                            .groupY = taskOrMeshIndirect.groupY,
                            .groupZ = taskOrMeshIndirect.groupZ,
                            .indirectBuf = assignerData.bufAssigns.getByKey(bufPassId),
                            .indirectBufOffset = taskOrMeshIndirect.indirectBufOffset,
                        };
                        filledPass.execution = .{ .taskOrMeshIndirect = taskMeshIndirectExec };
                    },
                }
            },
            .shaderInf => |shaderInf| {
                filledPass.shaderIds.appendAssumeCapacity(shaderInf.id);
            },
            .bufSlot => |bufSlot| {
                const bufPassId = try registryData.getBufferPassId(bufSlot.bufLink.in);
                const bufUse = BufferFill{
                    .bufId = assignerData.bufAssigns.getByKey(bufPassId),
                    .stage = bufSlot.stage,
                    .access = bufSlot.access,
                    .shaderSlot = bufSlot.shaderSlot,
                };
                filledPass.bufUses.appendAssumeCapacity(bufUse);
            },
            .texSlot => |texSlot| {
                const texPassId = try registryData.getTexturePassId(texSlot.texLink.in);
                const texUse = TextureFill{
                    .texId = assignerData.texAssigns.getByKey(texPassId),
                    .stage = texSlot.stage,
                    .access = texSlot.access,
                    .layout = texSlot.layout,
                    .descUse = texSlot.descUse,
                    .shaderSlot = texSlot.shaderSlot,
                };
                filledPass.texUses.appendAssumeCapacity(texUse);
            },
            .colorAtt => |attSlot| {
                const texPassId = try registryData.getTexturePassId(attSlot.texLink.in);
                const colorAttUse = AttachmentFill{
                    .texId = assignerData.texAssigns.getByKey(texPassId),
                    .stage = attSlot.stage,
                    .access = attSlot.access,
                    .layout = attSlot.layout,
                    .clear = if (attSlot.clear) |clear| clear else null,
                };
                filledPass.colorAtts.appendAssumeCapacity(colorAttUse);
            },
            .depthAtt => |depthSlot| {
                const texPassId = try registryData.getTexturePassId(depthSlot.texLink.in);
                filledPass.depthAtt = AttachmentFill{
                    .texId = assignerData.texAssigns.getByKey(texPassId),
                    .stage = depthSlot.stage,
                    .access = depthSlot.access,
                    .layout = depthSlot.layout,
                    .clear = depthSlot.clear,
                };
            },
            .stencilAtt => |stencilSlot| {
                const texPassId = try registryData.getTexturePassId(stencilSlot.texLink.in);
                filledPass.stencilAtt = AttachmentFill{
                    .texId = assignerData.texAssigns.getByKey(texPassId),
                    .stage = stencilSlot.stage,
                    .access = stencilSlot.access,
                    .layout = stencilSlot.layout,
                    .clear = stencilSlot.clear,
                };
            },
            .vertexBuffer => |vertexBufSlot| {
                const texPassId = try registryData.getBufferPassId(vertexBufSlot.bufInput);
                const vertBufUse = VertexBufferFill{
                    .bufId = assignerData.bufAssigns.getByKey(texPassId),
                    .binding = vertexBufSlot.binding,
                    .stride = vertexBufSlot.stride,
                    .inputRate = vertexBufSlot.inputRate,
                };
                filledPass.vertexBuffers.appendAssumeCapacity(vertBufUse);
            },
            .indexBuffer => |indexBufSlot| {
                const texPassId = try registryData.getBufferPassId(indexBufSlot.bufInput);
                filledPass.indexBuffer = IndexBufferFill{ .bufId = assignerData.bufAssigns.getByKey(texPassId), .indexType = indexBufSlot.indexType };
            },
            .vertexAttribute => |vertAttrib| {
                filledPass.vertexAttributes.appendAssumeCapacity(vertAttrib);
            },
            .renderState => |stateChange| switch (stateChange) {
                inline else => |val, tag| @field(filledPass.renderState, @tagName(tag)) = val,
            },
            .bufLinking, .texLinking => {},
        }
    }
    return filledPass;
}
