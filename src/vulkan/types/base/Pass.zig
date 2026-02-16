const ShaderId = @import("../../../core/ShaderCompiler.zig").ShaderInf.ShaderId;
const RenderState = @import("../base/RenderState.zig").RenderState;
const TextureMeta = @import("../res/TextureMeta.zig").TextureMeta;
const BufferMeta = @import("../res/BufferMeta.zig").BufferMeta;
const Texture = @import("../res/Texture.zig").Texture;
const Buffer = @import("../res/Buffer.zig").Buffer;
const vhE = @import("../../help/Enums.zig");

pub const Pass = struct {
    name: []const u8,
    shaderIds: []const ShaderId,
    bufUses: []const BufferUse = &.{},
    texUses: []const TextureUse = &.{},
    typ: PassType,

    pub const Dispatch = struct {
        x: u32,
        y: u32,
        z: u32,
    };

    pub const PassType = union(enum) {
        compute: ComputePass,
        classic: ClassicPass,
    };

    const ComputePass = struct {
        workgroups: Dispatch,
        mainTexId: ?TextureMeta.TexId = null,
    };

    pub const ClassicPass = struct {
        renderState: RenderState = .{},
        mainTexId: TextureMeta.TexId,
        colorAtts: []const Attachment,
        depthAtt: ?Attachment = null,
        stencilAtt: ?Attachment = null,

        classicTyp: ClassicTyp,
    };

    pub const ClassicTyp = union(enum) {
        graphics: Graphics,
        taskMesh: TaskMesh,

        const TaskMesh = struct {
            workgroups: Dispatch,
            indirectBuf: ?struct { id: BufferMeta.BufId, offset: u64 = 0 } = null,
        };

        pub fn taskMeshData(data: TaskMesh) ClassicTyp {
            return .{ .taskMesh = data };
        }

        const Graphics = struct {
            draw: struct { vertices: u32, instances: u32 } = .{ .vertices = 3, .instances = 1 },
        };

        pub fn graphicsData(data: Graphics) ClassicTyp {
            return .{ .graphics = data };
        }
    };

    pub fn createClassic(data: ClassicPass) Pass.PassType {
        return .{ .classic = data };
    }

    pub fn createCompute(data: ComputePass) Pass.PassType {
        return .{ .compute = data };
    }

    pub fn getMainTexId(self: *const Pass) ?TextureMeta.TexId {
        return switch (self.typ) {
            .classic => |classic| classic.mainTexId,
            .compute => |compute| compute.mainTexId,
        };
    }

    pub fn getColorAtts(self: *const Pass) []const Attachment {
        return switch (self.typ) {
            .classic => |classic| classic.colorAtts,
            .compute => &[_]Attachment{},
        };
    }

    pub fn getDepthAtt(self: *const Pass) ?Attachment {
        return switch (self.typ) {
            .classic => |classic| classic.depthAtt,
            .compute => null,
        };
    }

    pub fn getStencilAtt(self: *const Pass) ?Attachment {
        return switch (self.typ) {
            .classic => |classic| classic.stencilAtt,
            .compute => null,
        };
    }
};

pub const Attachment = struct {
    texId: TextureMeta.TexId,
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    layout: vhE.ImageLayout = .General,
    clear: bool,

    pub fn init(id: TextureMeta.TexId, stage: vhE.PipeStage, access: vhE.PipeAccess, clear: bool) Attachment {
        return .{ .texId = id, .stage = stage, .access = access, .layout = .Attachment, .clear = clear };
    }

    pub fn getNeededState(self: *const Attachment) Texture.TextureState {
        return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
    }
};

pub const TextureUse = struct {
    texId: TextureMeta.TexId,
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    layout: vhE.ImageLayout = .General,
    shaderSlot: ?u32 = null,

    pub fn init(id: TextureMeta.TexId, stage: vhE.PipeStage, access: vhE.PipeAccess, layout: vhE.ImageLayout, shaderSlot: ?u8) TextureUse {
        return .{ .texId = id, .stage = stage, .access = access, .layout = layout, .shaderSlot = if (shaderSlot) |slot| slot else null };
    }

    pub fn getNeededState(self: *const TextureUse) Texture.TextureState {
        return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
    }
};

pub const BufferUse = struct {
    bufId: BufferMeta.BufId,
    stage: vhE.PipeStage = .TopOfPipe,
    access: vhE.PipeAccess = .None,
    shaderSlot: ?u32 = null,

    pub fn init(bufId: BufferMeta.BufId, stage: vhE.PipeStage, access: vhE.PipeAccess, shaderSlot: ?u8) BufferUse {
        return .{ .bufId = bufId, .stage = stage, .access = access, .shaderSlot = if (shaderSlot) |slot| slot else null };
    }

    pub fn getNeededState(self: *const BufferUse) Buffer.BufferState {
        return .{ .stage = self.stage, .access = self.access };
    }
};
