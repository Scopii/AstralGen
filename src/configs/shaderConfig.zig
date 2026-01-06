const vk = @import("../modules/vk.zig").c;
const vh = @import("../vulkan/Helpers.zig");

// Shader Compilation
pub const SHADER_HOTLOAD = true;
pub const SHADER_STARTUP_COMPILATION = true;
pub const SHADER_MAX = 100;
// Paths
pub const rootPath: []const u8 = "../..";
pub const glslPath: []const u8 = "/src/shader";
pub const sprvPath: []const u8 = "/zig-out/shader";

pub const ShaderInf = struct {
    id: u8,
    shaderType: vh.ShaderStage,
    glslFile: []const u8,
    spvFile: []const u8,
};

pub const t1Comp = ShaderInf{ .id = 0, .shaderType = .compute, .glslFile = "compTest/comp.slang", .spvFile = "comp1.spv" };

pub const t2Vert = ShaderInf{ .id = 1, .shaderType = .vert, .glslFile = "grapTest/vert.slang", .spvFile = "vert1.spv" };
pub const t2Frag = ShaderInf{ .id = 2, .shaderType = .frag, .glslFile = "grapTest/frag.slang", .spvFile = "frag1.spv" };

pub const t3Mesh = ShaderInf{ .id = 3, .shaderType = .meshNoTask, .glslFile = "meshTest/mesh.slang", .spvFile = "mesh1.spv" };
pub const t3Frag = ShaderInf{ .id = 4, .shaderType = .frag, .glslFile = "meshTest/frag.slang", .spvFile = "frag2.spv" };

pub const t4Task = ShaderInf{ .id = 5, .shaderType = .task, .glslFile = "taskTest/task.slang", .spvFile = "task1.spv" };
pub const t4Mesh = ShaderInf{ .id = 6, .shaderType = .mesh, .glslFile = "taskTest/mesh.slang", .spvFile = "mesh2.spv" };
pub const t4Frag = ShaderInf{ .id = 7, .shaderType = .frag, .glslFile = "taskTest/frag.slang", .spvFile = "frag3.spv" };

pub const gridTask = ShaderInf{ .id = 8, .shaderType = .task, .glslFile = "gridTest/task.slang", .spvFile = "task2.spv" };
pub const gridMesh = ShaderInf{ .id = 9, .shaderType = .mesh, .glslFile = "gridTest/mesh.slang", .spvFile = "mesh3.spv" };
pub const gridFrag = ShaderInf{ .id = 10, .shaderType = .frag, .glslFile = "gridTest/frag.slang", .spvFile = "frag4.spv" };

pub const shadersToCompile: []const ShaderInf = &.{ t1Comp, t2Vert, t2Frag, t3Mesh, t3Frag, t4Task, t4Mesh, t4Frag, gridTask, gridMesh, gridFrag };
