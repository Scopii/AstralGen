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

pub const ShaderInfo = struct {
    id: u8,
    shaderType: vh.ShaderStage,
    glslFile: []const u8,
    spvFile: []const u8,
};

pub const t1Comp = ShaderInfo{ .id = 0, .shaderType = .compute, .glslFile = "compTest/comp.slang", .spvFile = "comp1.spv" };

pub const t2Vert = ShaderInfo{ .id = 1, .shaderType = .vert, .glslFile = "grapTest/vert.slang", .spvFile = "vert1.spv" };
pub const t2Frag = ShaderInfo{ .id = 2, .shaderType = .frag, .glslFile = "grapTest/frag.slang", .spvFile = "frag1.spv" };

pub const t3Mesh = ShaderInfo{ .id = 3, .shaderType = .meshNoTask, .glslFile = "meshTest/mesh.slang", .spvFile = "mesh1.spv" };
pub const t3Frag = ShaderInfo{ .id = 4, .shaderType = .frag, .glslFile = "meshTest/frag.slang", .spvFile = "frag2.spv" };

pub const t4Task = ShaderInfo{ .id = 5, .shaderType = .task, .glslFile = "taskTest/task.slang", .spvFile = "task1.spv" };
pub const t4Mesh = ShaderInfo{ .id = 6, .shaderType = .mesh, .glslFile = "taskTest/mesh.slang", .spvFile = "mesh2.spv" };
pub const t4Frag = ShaderInfo{ .id = 7, .shaderType = .frag, .glslFile = "taskTest/frag.slang", .spvFile = "frag3.spv" };

pub const gridTask = ShaderInfo{ .id = 8, .shaderType = .task, .glslFile = "gridTest/task.slang", .spvFile = "task2.spv" };
pub const gridMesh = ShaderInfo{ .id = 9, .shaderType = .mesh, .glslFile = "gridTest/mesh.slang", .spvFile = "mesh3.spv" };
pub const gridFrag = ShaderInfo{ .id = 10, .shaderType = .frag, .glslFile = "gridTest/frag.slang", .spvFile = "frag4.spv" };

pub const shadersToCompile: []const ShaderInfo = &.{ t1Comp, t2Vert, t2Frag, t3Mesh, t3Frag, t4Task, t4Mesh, t4Frag, gridTask, gridMesh, gridFrag };
