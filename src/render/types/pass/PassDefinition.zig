const RenderStateUnion = @import("../pass/RenderState.zig").RenderStateUnion;
const FixedList = @import("../../../.structures/FixedList.zig").FixedList;
const VertexBufferSlot = @import("VertexBufferSlot.zig").VertexBufferSlot;
const IndexBufferSlot = @import("IndexBufferSlot.zig").IndexBufferSlot;
const VertexAttribute = @import("VertexAttribute.zig").VertexAttribute;
const ShaderInf = @import("../../../shader/ShaderInf.zig").ShaderInf;
const AttachmentSlot = @import("AttachmentSlot.zig").AttachmentSlot;
const PassExecutionSlot = @import("PassDef.zig").PassDef.PassExecutionSlot;
const ShaderId = @import("../../../shader/ShaderSys.zig").ShaderId;
const RenderState = @import("../pass/RenderState.zig").RenderState;
const TexId = @import("../res/TextureMeta.zig").TextureMeta.TexId;
const TextureSlot = @import("TextureSlot.zig").TextureSlot;
const BufferSlot = @import("BufferSlot.zig").BufferSlot;
const std = @import("std");

const TextureStringLink = @import("../../../frameBuild/components.zig").TextureStringLink;
const BufferStringLink = @import("../../../frameBuild/components.zig").BufferStringLink;
const vhE = @import("../../help/Enums.zig");
const ClearColor = @import("AttachmentUse.zig").AttachmentUse.ClearColor;

const String = @import("../../../globalHelper.zig").String;

const AttributeCounts = struct {
    comps: u8 = 0,
    verts: u8 = 0,
    frags: u8 = 0,
    tasks: u8 = 0,
    bufAndTex: u8 = 0,
    meshForTasks: u8 = 0,
    meshOnly: u8 = 0,
    colorAtts: u8 = 0,
    depthAtts: u8 = 0,
    stencilAtts: u8 = 0,
    vertBufs: u8 = 0,
    indexBufs: u8 = 0,
    vertAttributes: u8 = 0,
    renderStateChanges: u8 = 0,
};

const MAX_PASS_ATTRIBUTES = 80;

pub const PassDefinition = struct {
    name: String(30, "PASS_NAME_MISSING") = .{},
    outputTex: ?[]const u8,
    passAttribute: FixedList(PassAttribute, MAX_PASS_ATTRIBUTES) = .{},

    pub const PassAttribute = union(enum) {
        execution: PassExecutionSlot,

        shaderInf: ShaderInf,
        bufSlot: BufferSlot,
        texSlot: TextureSlot,

        colorAtt: AttachmentSlot,
        depthAtt: AttachmentSlot,
        stencilAtt: AttachmentSlot,

        vertexBuffer: VertexBufferSlot,
        indexBuffer: IndexBufferSlot,
        vertexAttribute: VertexAttribute,

        renderState: RenderStateUnion,

        pub fn exec(passExec: PassExecutionSlot) PassAttribute {
            return .{ .execution = passExec };
        }

        pub fn shader(shaderInf: ShaderInf) PassAttribute {
            return .{ .shaderInf = shaderInf };
        }

        pub fn buf(bufLink: BufferStringLink, stage: vhE.PipeStage, bufUseKind: BufferSlot.BufUseKind, shaderSlot: ?u8) PassAttribute {
            return .{ .bufSlot = BufferSlot.init(bufLink, stage, bufUseKind, shaderSlot) };
        }

        pub fn tex(texLink: TextureStringLink, stage: vhE.PipeStage, texUseKind: TextureSlot.TextureUseKind, shaderSlot: ?u8) PassAttribute {
            return .{ .texSlot = TextureSlot.init(texLink, stage, texUseKind, shaderSlot) };
        }

        pub fn color(texLink: TextureStringLink, stage: vhE.PipeStage, access: vhE.PipeAccess, clear: ?ClearColor) PassAttribute {
            return .{ .colorAtt = AttachmentSlot.init(texLink, stage, access, clear) };
        }

        pub fn depth(texLink: TextureStringLink, stage: vhE.PipeStage, access: vhE.PipeAccess, clear: ?ClearColor) PassAttribute {
            return .{ .depthAtt = AttachmentSlot.init(texLink, stage, access, clear) };
        }

        pub fn stencil(texLink: TextureStringLink, stage: vhE.PipeStage, access: vhE.PipeAccess, clear: ?ClearColor) PassAttribute {
            return .{ .stencilAtt = AttachmentSlot.init(texLink, stage, access, clear) };
        }

        pub fn vertexBuf(bufInput: []const u8, binding: u32, stride: u32, inputRate: c_uint) PassAttribute {
            return .{ .vertexBuffer = VertexBufferSlot.init(bufInput, binding, stride, inputRate) };
        }

        pub fn indexBuf(bufInput: []const u8, indexType: c_uint) PassAttribute {
            return .{ .indexBuffer = IndexBufferSlot.init(bufInput, indexType) };
        }

        pub fn vertexAttrib(location: u32, binding: u32, format: c_uint, offset: u32) PassAttribute {
            return .{ .vertexAttribute = VertexAttribute.init(location, binding, format, offset) };
        }

        pub fn state(stateUnion: RenderStateUnion) PassAttribute {
            return .{ .renderState = stateUnion };
        }
    };

    // pub fn initComp(name: []const u8, execution: PassExecution.Com, outputTex: ?[]const u8, passAttributes: []const PassAttribute) !PassDefinition {
    //     try init(name, execution, outputTex, passAttributes);
    // }

    pub fn init(def: struct { name: []const u8, outputTex: ?[]const u8, passAttributes: []const PassAttribute }) PassDefinition {
        var passDef = PassDefinition{
            .outputTex = def.outputTex,
        };
        passDef.name.fill(def.name);
        std.debug.assert(def.passAttributes.len <= MAX_PASS_ATTRIBUTES);
        passDef.passAttribute.appendSliceAssumeCapacity(def.passAttributes);
        return passDef;
    }

    pub fn validate(self: *const PassDefinition) !void {
        var execution: ?PassExecutionSlot = null;
        var counts = AttributeCounts{};

        for (self.passAttribute.constSlice()) |attribute| {
            switch (attribute) {
                .execution => |exec| {
                    if (execution == null) execution = exec else {
                        std.debug.print("Pass {s} ERROR \n", .{self.name.get()});
                        return error.PassHasMoreThanOneExecution;
                    }
                },

                .shaderInf => |shaderInf| {
                    switch (shaderInf.typ) {
                        .comp => counts.comps += 1,
                        .vert => counts.verts += 1,
                        .task => counts.tasks += 1,
                        .meshWithTask => counts.meshForTasks += 1,
                        .meshNoTask => counts.meshOnly += 1,
                        .frag => counts.frags += 1,
                    }
                },

                .bufSlot => counts.bufAndTex += 1,
                .texSlot => counts.bufAndTex += 1,

                .colorAtt => counts.colorAtts += 1,
                .depthAtt => counts.depthAtts += 1,
                .stencilAtt => counts.stencilAtts += 1,

                .vertexBuffer => counts.vertBufs += 1,
                .indexBuffer => counts.indexBufs += 1,
                .vertexAttribute => counts.vertAttributes += 1,

                .renderState => counts.renderStateChanges += 1,
            }
        }

        if (counts.renderStateChanges > 31) return error.PassDefTooManyRenderChanges;

        if (counts.bufAndTex >= 14) return error.PassDefTooManyResources;

        if (execution) |exec| {
            switch (exec) {
                .compute => try isComputeValid(counts),
                .computeIndirect => try isComputeValid(counts),
                .taskOrMesh => try isTaskOrMeshValid(counts),
                .taskOrMeshIndirect => try isTaskOrMeshValid(counts),
                .graphics => try isGraphicsValid(counts),
            }
        } else {
            std.debug.print("ERROR: Pass {s} has no execution\n", .{self.name.get()});
            return error.PassHasNoExecution;
        }
    }

    pub fn isComputeValid(counts: AttributeCounts) !void {
        if (counts.comps != 1) return error.ComputePassNeedsCompShader;
        if (counts.verts != 0) return error.ComputePassHasVertShader;
        if (counts.frags != 0) return error.ComputePassHasFragShader;
        if (counts.tasks != 0) return error.ComputePassHasTaskShader;
        if (counts.meshForTasks != 0) return error.ComputePassHasMeshWithTaskShader;
        if (counts.meshOnly != 0) return error.ComputePassHasMeshNoTaskShader;

        if (counts.colorAtts != 0) return error.ComputePassHasColorAtts;
        if (counts.depthAtts != 0) return error.ComputePassHasDepthAtts;
        if (counts.stencilAtts != 0) return error.ComputePassHasStencilAtts;

        if (counts.vertBufs != 0) return error.ComputePassHasVertexBufs;
        if (counts.indexBufs != 0) return error.ComputePassHasIndexBufs;
        if (counts.vertAttributes != 0) return error.ComputePassHasVertAttributes;
    }

    pub fn isTaskOrMeshValid(counts: AttributeCounts) !void {
        if (counts.comps != 0) return error.GraphicsPassHasCompShader;
        if (counts.verts != 0) return error.GraphicsPassNeedsVertShader;
        if (counts.frags != 1) return error.GraphicsPassNeedsFragShader;

        const isValidMesh = (counts.tasks == 0 and counts.meshForTasks == 0 and counts.meshOnly == 1);
        const isValidTaskMesh = (counts.tasks == 1 and counts.meshForTasks == 1 and counts.meshOnly == 0);
        if (isValidMesh or isValidTaskMesh) {} else return error.MeshOrTaskPassNeedsInvalidShaders;

        if (counts.colorAtts > 8) return error.MeshOrTaskPassHasTooManyColorAtts;
        if (counts.depthAtts > 1) return error.MeshOrTaskPassHasTooManyDepthAtts;
        if (counts.stencilAtts > 1) return error.MeshOrTaskPassHasTooManyStencilAtts;

        if (counts.vertBufs != 0) return error.MeshOrTaskPassHasIndexBufs;
        if (counts.indexBufs != 0) return error.MeshOrTaskPassHasIndexBufs;
        if (counts.vertAttributes != 0) return error.MeshOrTaskPassHasVertAttributes;
    }

    pub fn isGraphicsValid(counts: AttributeCounts) !void {
        if (counts.comps != 0) return error.GraphicsPassHasCompShader;
        if (counts.verts != 1) return error.GraphicsPassNeedsVertShader;
        if (counts.frags != 1) return error.GraphicsPassNeedsFragShader;
        if (counts.tasks != 0) return error.GraphicsPassNeedsTaskShader;
        if (counts.meshForTasks != 0) return error.GraphicsPassHasMeshWithTaskShader;
        if (counts.meshOnly != 0) return error.GraphicsPassHasMeshNoTaskShader;

        if (counts.colorAtts > 8) return error.GraphicsPassHasTooManyColorAtts;
        if (counts.depthAtts > 1) return error.GraphicsPassHasTooManyDepthAtts;
        if (counts.stencilAtts > 1) return error.GraphicsPassHasTooManyStencilAtts;

        if (counts.vertBufs > 4) return error.GraphicsPassTooManyIndexBufs;
        if (counts.indexBufs > 1) return error.GraphicsPassHasTooManyIndexBufs;
        if (counts.vertAttributes > 16) return error.GraphicsPassHasTooManyVertAttributes;
    }
};
