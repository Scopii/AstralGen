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
    pub const ShaderId = packed struct { val: u8 };

    id: ShaderId,
    typ: vh.ShaderStage,
    glslFile: []const u8,
    spvFile: []const u8,
};

pub const t1Comp = ShaderInf{ .id = .{ .val = 0 }, .typ = .compute, .glslFile = "compTest/comp.slang", .spvFile = "comp1.spv" };

pub const t2Vert = ShaderInf{ .id = .{ .val = 1 }, .typ = .vert, .glslFile = "grapTest/vert.slang", .spvFile = "vert1.spv" };
pub const t2Frag = ShaderInf{ .id = .{ .val = 2 }, .typ = .frag, .glslFile = "grapTest/frag.slang", .spvFile = "frag1.spv" };

pub const t3Mesh = ShaderInf{ .id = .{ .val = 3 }, .typ = .meshNoTask, .glslFile = "meshTest/mesh.slang", .spvFile = "mesh1.spv" };
pub const t3Frag = ShaderInf{ .id = .{ .val = 4 }, .typ = .frag, .glslFile = "meshTest/frag.slang", .spvFile = "frag2.spv" };

pub const t4Task = ShaderInf{ .id = .{ .val = 5 }, .typ = .task, .glslFile = "taskTest/task.slang", .spvFile = "task1.spv" };
pub const t4Mesh = ShaderInf{ .id = .{ .val = 6 }, .typ = .mesh, .glslFile = "taskTest/mesh.slang", .spvFile = "mesh2.spv" };
pub const t4Frag = ShaderInf{ .id = .{ .val = 7 }, .typ = .frag, .glslFile = "taskTest/frag.slang", .spvFile = "frag3.spv" };

pub const gridTask = ShaderInf{ .id = .{ .val = 8 }, .typ = .task, .glslFile = "gridTest/task.slang", .spvFile = "task2.spv" };
pub const gridMesh = ShaderInf{ .id = .{ .val = 9 }, .typ = .mesh, .glslFile = "gridTest/mesh.slang", .spvFile = "mesh3.spv" };
pub const gridFrag = ShaderInf{ .id = .{ .val = 10 }, .typ = .frag, .glslFile = "gridTest/frag.slang", .spvFile = "frag4.spv" };

pub const shadersToCompile: []const ShaderInf = &.{ t1Comp, t2Vert, t2Frag, t3Mesh, t3Frag, t4Task, t4Mesh, t4Frag, gridTask, gridMesh, gridFrag };
