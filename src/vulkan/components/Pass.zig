const ShaderId = @import("../../configs/shaderConfig.zig").ShaderInf.ShaderId;
const TextureBase = @import("TextureBase.zig").TextureBase;
const Texture = @import("Texture.zig").Texture;
const Buffer = @import("Buffer.zig").Buffer;
const vh = @import("../systems/Helpers.zig");

pub const Pass = struct {
    name: []const u8,
    shaderIds: []const ShaderId,
    bufUses: []const BufferUse = &.{},
    texUses: []const TextureUse = &.{},
    typ: PassType,

    pub const Dispatch = struct { x: u32, y: u32, z: u32 };

    pub const PassType = union(enum) {
        compute: ComputePass,
        classic: ClassicPass,
    };

    const ComputePass = struct {
        workgroups: Dispatch,
        mainTexId: ?Texture.TexId = null,
    };

    pub const ClassicPass = struct {
        mainTexId: Texture.TexId,
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
            indirectBuf: ?struct { id: Buffer.BufId, offset: u64 = 0 } = null,
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

    pub fn getMainTexId(self: *const Pass) ?Texture.TexId {
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
    texId: Texture.TexId,
    stage: vh.PipeStage = .TopOfPipe,
    access: vh.PipeAccess = .None,
    layout: vh.ImageLayout = .General,
    clear: bool,

    pub fn init(id: Texture.TexId, stage: vh.PipeStage, access: vh.PipeAccess, clear: bool) Attachment {
        return .{ .texId = id, .stage = stage, .access = access, .layout = .Attachment, .clear = clear };
    }

    pub fn getNeededState(self: *const Attachment) TextureBase.TextureState {
        return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
    }
};

pub const ShaderSlot = packed struct { val: u32 };

pub const TextureUse = struct {
    texId: Texture.TexId,
    stage: vh.PipeStage = .TopOfPipe,
    access: vh.PipeAccess = .None,
    layout: vh.ImageLayout = .General,
    shaderSlot: ?ShaderSlot = null,

    pub fn init(id: Texture.TexId, stage: vh.PipeStage, access: vh.PipeAccess, layout: vh.ImageLayout, shaderSlot: ?u8) TextureUse {
        return .{ .texId = id, .stage = stage, .access = access, .layout = layout, .shaderSlot = if (shaderSlot) |slot| .{ .val = slot } else null };
    }

    pub fn getNeededState(self: *const TextureUse) TextureBase.TextureState {
        return .{ .stage = self.stage, .access = self.access, .layout = self.layout };
    }
};

pub const BufferUse = struct {
    bufId: Buffer.BufId,
    stage: vh.PipeStage = .TopOfPipe,
    access: vh.PipeAccess = .None,
    shaderSlot: ?ShaderSlot = null,

    pub fn init(bufId: Buffer.BufId, stage: vh.PipeStage, access: vh.PipeAccess, shaderSlot: ?u8) BufferUse {
        return .{ .bufId = bufId, .stage = stage, .access = access, .shaderSlot = if (shaderSlot) |slot| .{ .val = slot } else null };
    }

    pub fn getNeededState(self: *const BufferUse) Buffer.BufferState {
        return .{ .stage = self.stage, .access = self.access };
    }
};
