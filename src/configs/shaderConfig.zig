const vh = @import("../vulkan/systems/Helpers.zig");
const vk = @import("../modules/vk.zig").c;

// Shader Compilation
pub const SHADER_HOTLOAD = true;
pub const SHADER_STARTUP_COMPILATION = true;
pub const SHADER_MAX = 100;
// Paths
pub const rootPath: []const u8 = "../..";
pub const glslPath: []const u8 = "/src/shader";
pub const sprvPath: []const u8 = "/zig-out/shader";

pub const ShaderInf = struct {
    pub const ShaderId = packed struct { val: u8 };

    id: ShaderId,
    typ: vh.ShaderStage,
    glslFile: []const u8,
    spvFile: []const u8,
};

pub const t1Comp = ShaderInf{ .id = .{ .val = 0 }, .typ = .comp, .glslFile = "compTest/comp.slang", .spvFile = "t1Comp.spv" };

pub const t2Vert = ShaderInf{ .id = .{ .val = 1 }, .typ = .vert, .glslFile = "grapTest/vert.slang", .spvFile = "t2Vert.spv" };
pub const t2Frag = ShaderInf{ .id = .{ .val = 2 }, .typ = .frag, .glslFile = "grapTest/frag.slang", .spvFile = "t2Frag.spv" };

pub const t3Mesh = ShaderInf{ .id = .{ .val = 3 }, .typ = .meshNoTask, .glslFile = "meshTest/mesh.slang", .spvFile = "t3Mesh.spv" };
pub const t3Frag = ShaderInf{ .id = .{ .val = 4 }, .typ = .frag, .glslFile = "meshTest/frag.slang", .spvFile = "t3Frag.spv" };

pub const t4Task = ShaderInf{ .id = .{ .val = 5 }, .typ = .task, .glslFile = "taskTest/task.slang", .spvFile = "t4Task.spv" };
pub const t4Mesh = ShaderInf{ .id = .{ .val = 6 }, .typ = .mesh, .glslFile = "taskTest/mesh.slang", .spvFile = "t4Mesh.spv" };
pub const t4Frag = ShaderInf{ .id = .{ .val = 7 }, .typ = .frag, .glslFile = "taskTest/frag.slang", .spvFile = "t4Frag.spv" };

pub const gridTask = ShaderInf{ .id = .{ .val = 8 }, .typ = .task, .glslFile = "gridTest/task.slang", .spvFile = "gridTask.spv" };
pub const gridMesh = ShaderInf{ .id = .{ .val = 9 }, .typ = .mesh, .glslFile = "gridTest/mesh.slang", .spvFile = "gridMesh.spv" };
pub const gridFrag = ShaderInf{ .id = .{ .val = 10 }, .typ = .frag, .glslFile = "gridTest/frag.slang", .spvFile = "gridFrag.spv" };

pub const indirectComp = ShaderInf{ .id = .{ .val = 11 }, .typ = .comp, .glslFile = "indirectTest/comp.slang", .spvFile = "indirectComp.spv" };
pub const indirectTask = ShaderInf{ .id = .{ .val = 12 }, .typ = .task, .glslFile = "indirectTest/task.slang", .spvFile = "indirectTask.spv" };
pub const indirectMesh = ShaderInf{ .id = .{ .val = 13 }, .typ = .mesh, .glslFile = "indirectTest/mesh.slang", .spvFile = "indirectMesh.spv" };
pub const indirectFrag = ShaderInf{ .id = .{ .val = 14 }, .typ = .frag, .glslFile = "indirectTest/frag.slang", .spvFile = "indirectFrag.spv" };

pub const shadersToCompile: []const ShaderInf = &.{
    t1Comp,

    t2Vert,
    t2Frag,

    t3Mesh,
    t3Frag,

    t4Task,
    t4Mesh,
    t4Frag,

    gridTask,
    gridMesh,
    gridFrag,
    
    indirectComp,
    indirectTask,
    indirectMesh,
    indirectFrag
};
