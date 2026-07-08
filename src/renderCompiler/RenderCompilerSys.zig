const RenderAssignerData = @import("../renderAssigner/RenderAssignerData.zig").RenderAssignerData;
const RenderRegistryData = @import("../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const RenderGraphData = @import("../renderGraph/RenderGraphData.zig").RenderGraphData;
const RenderCompilerData = @import("RenderCompilerData.zig").RenderCompilerData;
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

const TaskOrMeshIndirectExec = @import("../render/types/pass/PassInstance.zig").TaskOrMeshIndirectExec;
const ComputeIndirectExec = @import("../render/types/pass/PassInstance.zig").ComputeIndirectExec;
const VertexBufferFill = @import("../render/types/pass/VertexBufferFill.zig").VertexBufferFill;
const IndexBufferFill = @import("../render/types/pass/IndexBufferFill.zig").IndexBufferFill;
const VertexAttribute = @import("../render/types/pass/VertexAttribute.zig").VertexAttribute;
const AttachmentFill = @import("../render/types/pass/AttachmentFill.zig").AttachmentFill;
const PassInstance = @import("../render/types/pass/PassInstance.zig").PassInstance;
const TextureFill = @import("../render/types/pass/TextureFill.zig").TextureFill;
const BufferFill = @import("../render/types/pass/BufferFill.zig").BufferFill;
const PassId = @import("../.configs/idConfig.zig").PassId;

pub const RenderCompilerSys = struct {
    pub fn compileIR(self: *RenderCompilerData, assigner: *const RenderAssignerData, renderGraph: *const RenderGraphData, registry: *const RenderRegistryData) !void {
        self.sortedNodes.clear();

        for (renderGraph.sorter.sortedRenderIR.constSlice()) |IR| {
            switch (IR) {
                // .uiIR => |uiIR| {},
                .blitIR => |blitIR| {
                    var blitCopy = blitIR;

                    switch (blitIR.srcTexUnion) {
                        .texName => |name| {
                            const texPassId = try registry.getTexturePassId(name);
                            const hardwareTexId = assigner.texAssigns.getByKey(texPassId);
                            blitCopy.srcTexUnion = .{ .texId = hardwareTexId };
                        },
                        .texPassId => |texPassId| {
                            const hardwareTexId = assigner.texAssigns.getByKey(texPassId);
                            blitCopy.srcTexUnion = .{ .texId = hardwareTexId };
                        },
                        .texId => {},
                    }
                    self.sortedNodes.append(.{ .blitNode = blitCopy }) catch std.debug.print("7.PassSorter: Blit Append to sortedRenderNodes failed", .{});
                },
                .compositeIR => |compositeIR| {
                    var compositeCopy = compositeIR;

                    switch (compositeCopy.srcTexUnion) {
                        .texName => |name| {
                            const texPassId = try registry.getTexturePassId(name);
                            const hardwareTexId = assigner.texAssigns.getByKey(texPassId);
                            compositeCopy.srcTexUnion = .{ .texId = hardwareTexId };
                        },
                        .texPassId => |texPassId| {
                            const hardwareTexId = assigner.texAssigns.getByKey(texPassId);
                            compositeCopy.srcTexUnion = .{ .texId = hardwareTexId };
                        },
                        .texId => {},
                    }
                    self.sortedNodes.append(.{ .compositeNode = compositeCopy }) catch std.debug.print("7.PassSorter: Composite Append to sortedRenderNodes failed", .{});
                },
                .passIR => |passIR| {
                    const passInstance = try fillPassHardwareIds(assigner, registry, passIR);
                    self.sortedNodes.append(.{ .passNode = passInstance }) catch std.debug.print("7.PassSorter: Pass Append to sortedRenderNodes failed", .{});
                },
                .clearBufIR => |clearBufIR| {
                    const hardwareTexId = assigner.bufAssigns.getByKey(clearBufIR);
                    try self.sortedNodes.append(.{ .clearBuffer = hardwareTexId });
                },
                .clearTexIR => |clearTexIR| {
                    const hardwareTexId = assigner.texAssigns.getByKey(clearTexIR);
                    try self.sortedNodes.append(.{ .clearTexture = hardwareTexId });
                },
                .barrierBakeClears => |barrierBakeClears| {
                    try self.sortedNodes.append(.{ .barrierBakeClears = barrierBakeClears });
                },
            }
        }

        // Debug Prints
        if (rc.FRAME_GRAPH_DEBUG or true) {
            std.debug.print("Pass Resource Sys:\n", .{});
            for (self.sortedNodes.constSlice(), 0..) |*renderNode, index| {
                switch (renderNode.*) {
                    .passNode => |*passNode| std.debug.print("- {}. Pass: {s}\n", .{ index, passNode.getName() }),
                    .compositeNode => |*composite| std.debug.print("- {}. Composite: {s} (Pass {s})\n", .{ index, composite.name, try registry.getPassName(composite.pass) }),
                    .blitNode => |*blit| std.debug.print("- {}. Blit: {s} (Pass {s})\n", .{ index, blit.name, try registry.getPassName(blit.pass) }),
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

fn fillPassHardwareIds(assigner: *const RenderAssignerData, registry: *const RenderRegistryData, passId: PassId) !PassInstance {
    const passName = try registry.getPassName(passId);
    const passDef = try registry.getPassDefinition(passName);
    const mainOutputTexId = if (passDef.outputTex) |output| try registry.getTexturePassId(output) else null;

    var filledPass = PassInstance{
        .name = undefined,
        .execution = undefined,
        .mainOutputTex = if (mainOutputTexId) |outputId| assigner.texAssigns.getByKey(outputId) else null,
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
                        const bufPassId = try registry.getBufferPassId(compIndirect.indirectBuf);
                        const compIndirectExec = ComputeIndirectExec{
                            .indirectBuf = assigner.bufAssigns.getByKey(bufPassId),
                            .indirectBufOffset = compIndirect.indirectBufOffset,
                        };
                        filledPass.execution = .{ .computeIndirect = compIndirectExec };
                    },
                    .taskOrMeshIndirect => |taskOrMeshIndirect| {
                        const bufPassId = try registry.getBufferPassId(taskOrMeshIndirect.indirectBuf);
                        const taskMeshIndirectExec = TaskOrMeshIndirectExec{
                            .groupX = taskOrMeshIndirect.groupX,
                            .groupY = taskOrMeshIndirect.groupY,
                            .groupZ = taskOrMeshIndirect.groupZ,
                            .indirectBuf = assigner.bufAssigns.getByKey(bufPassId),
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
                const bufPassId = try registry.getBufferPassId(bufSlot.bufLink.in);
                const bufUse = BufferFill{
                    .bufId = assigner.bufAssigns.getByKey(bufPassId),
                    .stage = bufSlot.stage,
                    .access = bufSlot.access,
                    .shaderSlot = bufSlot.shaderSlot,
                };
                filledPass.bufUses.appendAssumeCapacity(bufUse);
            },
            .texSlot => |texSlot| {
                const texPassId = try registry.getTexturePassId(texSlot.texLink.in);
                const texUse = TextureFill{
                    .texId = assigner.texAssigns.getByKey(texPassId),
                    .stage = texSlot.stage,
                    .access = texSlot.access,
                    .layout = texSlot.layout,
                    .descUse = texSlot.descUse,
                    .shaderSlot = texSlot.shaderSlot,
                };
                filledPass.texUses.appendAssumeCapacity(texUse);
            },
            .colorAtt => |attSlot| {
                const texPassId = try registry.getTexturePassId(attSlot.texLink.in);
                const colorAttUse = AttachmentFill{
                    .texId = assigner.texAssigns.getByKey(texPassId),
                    .stage = attSlot.stage,
                    .access = attSlot.access,
                    .layout = attSlot.layout,
                    .clear = if (attSlot.clear) |clear| clear else null,
                };
                filledPass.colorAtts.appendAssumeCapacity(colorAttUse);
            },
            .depthAtt => |depthSlot| {
                const texPassId = try registry.getTexturePassId(depthSlot.texLink.in);
                filledPass.depthAtt = AttachmentFill{
                    .texId = assigner.texAssigns.getByKey(texPassId),
                    .stage = depthSlot.stage,
                    .access = depthSlot.access,
                    .layout = depthSlot.layout,
                    .clear = depthSlot.clear,
                };
            },
            .stencilAtt => |stencilSlot| {
                const texPassId = try registry.getTexturePassId(stencilSlot.texLink.in);
                filledPass.stencilAtt = AttachmentFill{
                    .texId = assigner.texAssigns.getByKey(texPassId),
                    .stage = stencilSlot.stage,
                    .access = stencilSlot.access,
                    .layout = stencilSlot.layout,
                    .clear = stencilSlot.clear,
                };
            },
            .vertexBuffer => |vertexBufSlot| {
                const texPassId = try registry.getBufferPassId(vertexBufSlot.bufInput);
                const vertBufUse = VertexBufferFill{
                    .bufId = assigner.bufAssigns.getByKey(texPassId),
                    .binding = vertexBufSlot.binding,
                    .stride = vertexBufSlot.stride,
                    .inputRate = vertexBufSlot.inputRate,
                };
                filledPass.vertexBuffers.appendAssumeCapacity(vertBufUse);
            },
            .indexBuffer => |indexBufSlot| {
                const texPassId = try registry.getBufferPassId(indexBufSlot.bufInput);
                filledPass.indexBuffer = IndexBufferFill{ .bufId = assigner.bufAssigns.getByKey(texPassId), .indexType = indexBufSlot.indexType };
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
