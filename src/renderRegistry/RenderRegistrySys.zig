const TaskOrMeshIndirectExecFill = @import("../render/types/pass/PassDefinition.zig").TaskOrMeshIndirectExecFill;
const ComputeIndirectExecFill = @import("../render/types/pass/PassDefinition.zig").ComputeIndirectExecFill;
const VertexIndexedExec = @import("../render/types/pass/PassDefinition.zig").VertexIndexedExec;
const PassExecutionFill = @import("../render/types/pass/PassDefinition.zig").PassExecutionFill;
const VertexBufferFill = @import("../render/types/pass/VertexBufferUse.zig").VertexBufferFill;
const IndexBufferFill = @import("../render/types/pass/IndexBufferUse.zig").IndexBufferFill;
const TaskOrMeshExec = @import("../render/types/pass/PassDefinition.zig").TaskOrMeshExec;
const PassDefinition = @import("../render/types/pass/PassDefinition.zig").PassDefinition;
const AttachmentFill = @import("../render/types/pass/AttachmentUse.zig").AttachmentFill;
const PassProperty = @import("../render/types/pass/PassDefinition.zig").PassProperty;
const TexDesc = @import("../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const ComputeExec = @import("../render/types/pass/PassDefinition.zig").ComputeExec;
const VertexExec = @import("../render/types/pass/PassDefinition.zig").VertexExec;
const BufDesc = @import("../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const RenderRegistryData = @import("RenderRegistryData.zig").RenderRegistryData;
const TextureFill = @import("../render/types/pass/TextureUse.zig").TextureFill;
const BufferFill = @import("../render/types/pass/BufferUse.zig").BufferFill;
const Pass = @import("../render/types/pass/PassDefinition.zig").Pass;
const BufPassId = @import("../.configs/idConfig.zig").BufPassId;
const TexPassId = @import("../.configs/idConfig.zig").TexPassId;
const PassId = @import("../.configs/idConfig.zig").PassId;
const rc = @import("../.configs/renderConfig.zig");
const std = @import("std");

const depthViewPass = @import("../.assets/passes/depthView/DepthView.zig").depthViewPass;
const compRayMarchPass = @import("../.assets/passes/compTest/CompRayMarch.zig").compRayMarchPass;
const editorGridGridDebugPass = @import("../.assets/passes/editorGrid/EditorGrid.zig").editorGridGridDebugPass;
const editorGridPlaneDebugPass = @import("../.assets/passes/editorGrid/EditorGrid.zig").editorGridPlaneDebugPass;
const frustumViewPass = @import("../.assets/passes/quant/FrustumView.zig").frustumViewPass;
const quantGridPass = @import("../.assets/passes/quant/Quant.zig").quantGridPass;
const quantGridDebugPass = @import("../.assets/passes/quant/Quant.zig").quantGridDebugPass;
const quantPlanePass = @import("../.assets/passes/quant/Quant.zig").quantPlanePass;
const quantPlaneDebugPass = @import("../.assets/passes/quant/Quant.zig").quantPlaneDebugPass;
const quantCompPass = @import("../.assets/passes/quant/QuantComp.zig").quantCompPass;

pub const RenderRegistrySys = struct {
    pub fn init(self: *RenderRegistryData, alloc: std.mem.Allocator) !void {
        self.passIdMap = std.StringHashMap(PassId).init(alloc);
        try self.passIdMap.ensureTotalCapacity(rc.PASS_MAX);

        self.bufPassIdMap = std.StringHashMap(BufPassId).init(alloc);
        try self.bufPassIdMap.ensureTotalCapacity(rc.BUF_MAX);

        self.texPassIdMap = std.StringHashMap(TexPassId).init(alloc);
        try self.texPassIdMap.ensureTotalCapacity(rc.TEX_MAX);
    }

    pub fn deinit(self: *RenderRegistryData) void {
        self.passIdMap.deinit();
        self.bufPassIdMap.deinit();
        self.texPassIdMap.deinit();
    }

    pub fn addPassDefinition(registry: *RenderRegistryData, passDef: PassDefinition) !void {
        try passDef.validate();
        const passName = passDef.name.get();

        if (registry.passIdMap.contains(passName) == true) {
            std.debug.print("ERROR: Pass Definition ({s}) already Exists\n", .{passName});
            return error.PassNameAlreadyExists;
        }
        const passId: PassId = .id(registry.passPool.tryReserveKey() orelse return error.noFreePassId);

        var pass: Pass = .{
            .name = passDef.name,
            .renderScaling = passDef.renderScaling,
            .outputTex = if (passDef.outputTex) |outputTex| try registry.getTexturePassId(outputTex) else null,
            .execution = switch (passDef.execution) {
                .compute => |comp| PassExecutionFill{ .compute = comp },
                .computeIndirect => |compIndirect| PassExecutionFill{
                    .computeIndirect = .{ .indirectBuf = try registry.getBufferPassId(compIndirect.indirectBuf), .indirectBufOffset = compIndirect.indirectBufOffset },
                },
                .taskOrMesh => |taskOrMesh| PassExecutionFill{ .taskOrMesh = taskOrMesh },
                .taskOrMeshIndirect => |taskOrMeshExec| PassExecutionFill{
                    .taskOrMeshIndirect = .{ .indirectBufId = try registry.getBufferPassId(taskOrMeshExec.indirectBuf), .bufOffset = taskOrMeshExec.bufOffset },
                },
                .vertex => |vertex| PassExecutionFill{ .vertex = vertex },
                .vertexIndexed => |vertexIndexed| PassExecutionFill{ .vertexIndexed = vertexIndexed },
            },
        };

        for (passDef.passAttributes.constSlice()) |passAttrib| {
            const newProperty = switch (passAttrib) {
                .shaderInf => |shaderInf| PassProperty{ .shaderInf = shaderInf },

                .vertexAttribute => |vertexAttribute| PassProperty{ .vertexAttribute = vertexAttribute },
                
                .renderState => |renderState| PassProperty{ .renderState = renderState },

                .passLink => |passLink| PassProperty{ .passLink = try registry.getPassId(passLink.predecessor) },

                .bufLink => |bufLink| PassProperty{ .bufLink = .{ .in = try registry.getBufferPassId(bufLink.in), .from = if (bufLink.from) |from| try registry.getPassId(from) else null } },

                .texLink => |texLink| PassProperty{ .texLink = .{ .in = try registry.getTexturePassId(texLink.in), .from = if (texLink.from) |from| try registry.getPassId(from) else null } },

                .indexBuffer => |indexBuffer| PassProperty{ .indexBuffer = IndexBufferFill{ .bufPassId = try registry.getBufferPassId(indexBuffer.bufInput), .indexType = indexBuffer.indexType } },

                .vertexBuffer => |vertexBuffer| PassProperty{
                    .vertexBuffer = VertexBufferFill{
                        .bufPassId = try registry.getBufferPassId(vertexBuffer.bufInput),
                        .binding = vertexBuffer.binding,
                        .stride = vertexBuffer.stride,
                        .inputRate = vertexBuffer.inputRate,
                    },
                },

                .bufSlot => |bufSlot| PassProperty{
                    .bufSlot = BufferFill{
                        .bufLink = .{ .in = try registry.getBufferPassId(bufSlot.bufLink.in), .from = if (bufSlot.bufLink.from) |from| try registry.getPassId(from) else null },
                        .stage = bufSlot.stage,
                        .access = bufSlot.access,
                        .shaderSlot = bufSlot.shaderSlot,
                    },
                },

                .texSlot => |texSlot| PassProperty{
                    .texSlot = TextureFill{
                        .texLink = .{ .in = try registry.getTexturePassId(texSlot.texLink.in), .from = if (texSlot.texLink.from) |from| try registry.getPassId(from) else null },
                        .stage = texSlot.stage,
                        .access = texSlot.access,
                        .layout = texSlot.layout,
                        .descUse = texSlot.descUse,
                        .shaderSlot = texSlot.shaderSlot,
                    },
                },

                .colorAtt => |colorAtt| PassProperty{
                    .colorAtt = AttachmentFill{
                        .texLink = .{ .in = try registry.getTexturePassId(colorAtt.texLink.in), .from = if (colorAtt.texLink.from) |from| try registry.getPassId(from) else null },
                        .stage = colorAtt.stage,
                        .access = colorAtt.access,
                        .layout = colorAtt.layout,
                        .clear = colorAtt.clear,
                    },
                },

                .depthAtt => |depthAtt| PassProperty{
                    .depthAtt = AttachmentFill{
                        .texLink = .{ .in = try registry.getTexturePassId(depthAtt.texLink.in), .from = if (depthAtt.texLink.from) |from| try registry.getPassId(from) else null },
                        .stage = depthAtt.stage,
                        .access = depthAtt.access,
                        .layout = depthAtt.layout,
                        .clear = depthAtt.clear,
                    },
                },

                .stencilAtt => |stencilAtt| PassProperty{
                    .stencilAtt = AttachmentFill{
                        .texLink = .{ .in = try registry.getTexturePassId(stencilAtt.texLink.in), .from = if (stencilAtt.texLink.from) |from| try registry.getPassId(from) else null },
                        .stage = stencilAtt.stage,
                        .access = stencilAtt.access,
                        .layout = stencilAtt.layout,
                        .clear = stencilAtt.clear,
                    },
                },
            };

            try pass.passProperties.append(newProperty);
        }

        registry.passes.upsert(passId, pass);
        registry.passNames.upsert(passId, try .string(passName));

        const persistentName = registry.passNames.getConstPtrByKey(passId).get();
        registry.passIdMap.putAssumeCapacity(persistentName, passId);
    }

    pub fn removePassDefinition(registry: *RenderRegistryData, name: []const u8) void {
        if (registry.passIdMap.get(name)) |passId| {
            registry.passIdMap.remove(name);
            registry.passes.remove(passId);
            registry.passNames.remove(passId);
            registry.passPool.freeKey(passId.val());
        }
    }

    pub fn addTextureDefinition(registry: *RenderRegistryData, newName: []const u8, newTexDesc: TexDesc) !void {
        if (registry.texPassIdMap.contains(newName) == true) {
            std.debug.print("ERROR: Texture Definition ({s}) already Exists\n", .{newName});
            return error.TextureNameAlreadyExists;
        }
        const texPassId: TexPassId = .id(registry.texPool.tryReserveKey() orelse return error.noFreeTexPassId);

        registry.texDefinitions.upsert(texPassId, newTexDesc);
        registry.texNames.upsert(texPassId, try .string(newName));

        const persistentName = registry.texNames.getConstPtrByKey(texPassId).get();
        registry.texPassIdMap.putAssumeCapacity(persistentName, texPassId);
    }

    pub fn removeTextureDefinitionByString(registry: *RenderRegistryData, name: []const u8) void {
        if (registry.texPassIdMap.get(name)) |texPassId| {
            registry.texPassIdMap.remove(name);
            registry.texDefinitions.remove(texPassId);
            registry.texNames.remove(texPassId);
            registry.texPool.freeKey(texPassId.val());
        }
    }

    pub fn addBufferDefinition(registry: *RenderRegistryData, newName: []const u8, newBufDesc: BufDesc) !void {
        if (registry.bufPassIdMap.contains(newName) == true) {
            std.debug.print("ERROR: Buffer Definition ({s}) already Exists\n", .{newName});
            return error.BufferNameAlreadyExists;
        }
        const bufPassId: BufPassId = .id(registry.bufPool.tryReserveKey() orelse return error.noFreeBufPassId);

        registry.bufDefinitions.upsert(bufPassId, newBufDesc);
        registry.bufNames.upsert(bufPassId, try .string(newName));

        const persistentName = registry.bufNames.getConstPtrByKey(bufPassId).get();
        registry.bufPassIdMap.putAssumeCapacity(persistentName, bufPassId);
    }

    pub fn removeBufferDefinition(registry: *RenderRegistryData, name: []const u8) void {
        if (registry.bufPassIdMap.get(name)) |bufPassId| {
            registry.bufPassIdMap.remove(name);
            registry.bufDefinitions.remove(bufPassId);
            registry.bufNames.remove(bufPassId);
            registry.bufPool.freeKey(bufPassId.val());
        }
    }

    pub fn setupDefinitions(self: *RenderRegistryData) !void {
        // Buffers
        try RenderRegistrySys.addBufferDefinition(self, "QuantIndirectSB", rc.INDIRECT_SB);
        try RenderRegistrySys.addBufferDefinition(self, "ReadbackSB", rc.READBACK_SB);

        try RenderRegistrySys.addBufferDefinition(self, "EntitySB", rc.ENTITY_SB);
        try RenderRegistrySys.addBufferDefinition(self, "MainCamUB", rc.CAMERA_UB);
        try RenderRegistrySys.addBufferDefinition(self, "DebugCamUB", rc.CAMERA_UB);

        try RenderRegistrySys.addBufferDefinition(self, "ImguiVB", rc.IMGUI_VB);
        try RenderRegistrySys.addBufferDefinition(self, "ImguiIB", rc.IMGUI_IB);

        // Textures
        try RenderRegistrySys.addTextureDefinition(self, "RayMarchTex", rc.TRANSIENT_COLOR_TEX);

        try RenderRegistrySys.addTextureDefinition(self, "GridTex", rc.TRANSIENT_ATT_TEX);
        try RenderRegistrySys.addTextureDefinition(self, "GridDepthTex", rc.TRANSIENT_DEPTH_TEX);

        try RenderRegistrySys.addTextureDefinition(self, "DebugGridTex", rc.TRANSIENT_ATT_TEX);
        try RenderRegistrySys.addTextureDefinition(self, "DebugGridDepthTex", rc.TRANSIENT_DEPTH_TEX);

        try RenderRegistrySys.addTextureDefinition(self, "PlaneTex", rc.TRANSIENT_ATT_TEX);
        try RenderRegistrySys.addTextureDefinition(self, "PlaneDepthTex", rc.TRANSIENT_DEPTH_TEX);

        try RenderRegistrySys.addTextureDefinition(self, "DebugPlaneTex", rc.TRANSIENT_ATT_TEX);
        try RenderRegistrySys.addTextureDefinition(self, "DebugPlaneDepthTex", rc.TRANSIENT_DEPTH_TEX);

        try RenderRegistrySys.addTextureDefinition(self, "DepthViewTex", rc.TRANSIENT_COLOR_TEX);

        try RenderRegistrySys.addTextureDefinition(self, "TestTileTex", rc.PERSISTENT_COLOR_TEX);
        try RenderRegistrySys.addTextureDefinition(self, "ImguiFontTex", rc.IMGUI_FONT_TEX);

        try RenderRegistrySys.addPassDefinition(self, quantCompPass);

        try RenderRegistrySys.addPassDefinition(self, quantGridPass);
        try RenderRegistrySys.addPassDefinition(self, quantGridDebugPass);
        try RenderRegistrySys.addPassDefinition(self, quantPlanePass);
        try RenderRegistrySys.addPassDefinition(self, quantPlaneDebugPass);

        try RenderRegistrySys.addPassDefinition(self, frustumViewPass);

        try RenderRegistrySys.addPassDefinition(self, editorGridPlaneDebugPass);
        try RenderRegistrySys.addPassDefinition(self, editorGridGridDebugPass);

        try RenderRegistrySys.addPassDefinition(self, depthViewPass);
        try RenderRegistrySys.addPassDefinition(self, compRayMarchPass);
    }
};
