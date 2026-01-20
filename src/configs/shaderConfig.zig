const vkE = @import("../vulkan/help/Enums.zig");

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
    typ: vkE.ShaderStage,
    file: []const u8,
    spvFile: []const u8,

    pub fn create(id: u32, typ: vkE.ShaderStage, file: []const u8, spvFile: []const u8) ShaderInf {
        return .{ .id = .{ .val = id }, .typ = typ, .file = file, .spvFile = spvFile };
    }
};

pub const t1Comp = ShaderInf.create(0, .comp, "compTest/comp.slang", "t1Comp.spv");

pub const t2Vert = ShaderInf.create(1, .vert, "grapTest/vert.slang", "t2Vert.spv");
pub const t2Frag = ShaderInf.create(2, .frag, "grapTest/frag.slang", "t2Frag.spv");

pub const t3Mesh = ShaderInf.create(3, .meshNoTask, "meshTest/mesh.slang", "t3Mesh.spv");
pub const t3Frag = ShaderInf.create(4, .frag, "meshTest/frag.slang", "t3Frag.spv");

pub const t4Task = ShaderInf.create(5, .task, "taskTest/task.slang", "t4Task.spv");
pub const t4Mesh = ShaderInf.create(6, .mesh, "taskTest/mesh.slang", "t4Mesh.spv");
pub const t4Frag = ShaderInf.create(7, .frag, "taskTest/frag.slang", "t4Frag.spv");

pub const gridTask = ShaderInf.create(8, .task, "gridTest/task.slang", "gridTask.spv");
pub const gridMesh = ShaderInf.create(9, .mesh, "gridTest/mesh.slang", "gridMesh.spv");
pub const gridFrag = ShaderInf.create(10, .frag, "gridTest/frag.slang", "gridFrag.spv");

pub const indirectComp = ShaderInf.create(11, .comp, "indirectTest/comp.slang", "indirectComp.spv");
pub const indirectTask = ShaderInf.create(12, .task, "indirectTest/task.slang", "indirectTask.spv");
pub const indirectMesh = ShaderInf.create(13, .mesh, "indirectTest/mesh.slang", "indirectMesh.spv");
pub const indirectFrag = ShaderInf.create(14, .frag, "indirectTest/frag.slang", "indirectFrag.spv");

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
    indirectFrag,
};
