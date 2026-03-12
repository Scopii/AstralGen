const vkE = @import("../vulkan/help/Enums.zig");
const ShaderInf = @import("../core/ShaderInf.zig").ShaderInf;

// Shader Compilation
pub const SHADER_HOTLOAD = true;
pub const SHADER_STARTUP_COMPILATION = true;
pub const SHADER_MAX = 31;
// Paths
pub const ROOT_PATH: []const u8 = "../..";
pub const SHADER_PATH: []const u8 = "assets/shaders";
pub const SPRV_PATH: []const u8 = "zig-out/shaders";

// Shaders
pub const cullTestComp = ShaderInf.init(20, .comp, "cullTest/comp.slang", "cullTestComp.spv");
pub const cullTestMesh = ShaderInf.init(22, .meshNoTask, "cullTest/mesh.slang", "cullTestMesh.spv");
pub const frustumMesh = ShaderInf.init(23, .meshNoTask, "cullTest/frustum.slang", "frustumMesh.spv");
pub const cullTestFrag = ShaderInf.init(24, .frag, "cullTest/frag.slang", "cullTestFrag.spv");

pub const quantComp = ShaderInf.init(25, .comp, "quant/comp.slang", "quantComp.spv");
pub const quantMesh = ShaderInf.init(26, .meshNoTask, "quant/mesh.slang", "quantMesh.spv");
pub const quantFrag = ShaderInf.init(27, .frag, "quant/frag.slang", "quantFrag.spv");

pub const editorGridMesh = ShaderInf.init(28, .meshNoTask, "editorGrid/mesh.slang", "editorGridMesh.spv");
pub const editorGridFrag = ShaderInf.init(29, .frag, "editorGrid/frag.slang", "editorGridFrag.spv");

pub const COMPILING_SHADERS: []const ShaderInf = &.{
    cullTestComp,
    cullTestMesh,
    frustumMesh,
    cullTestFrag,

    quantComp,
    quantMesh,
    quantFrag,

    editorGridMesh,
    editorGridFrag,
};

// pub const t1Comp = ShaderInf.init(0, .comp, "compTest/comp.slang", "t1Comp.spv");

// pub const t2Vert = ShaderInf.init(1, .vert, "grapTest/vert.slang", "t2Vert.spv");
// pub const t2Frag = ShaderInf.init(2, .frag, "grapTest/frag.slang", "t2Frag.spv");

// pub const t3Mesh = ShaderInf.init(3, .meshNoTask, "meshTest/mesh.slang", "t3Mesh.spv");
// pub const t3Frag = ShaderInf.init(4, .frag, "meshTest/frag.slang", "t3Frag.spv");

// pub const t4Task = ShaderInf.init(5, .task, "taskTest/task.slang", "t4Task.spv");
// pub const t4Mesh = ShaderInf.init(6, .mesh, "taskTest/mesh.slang", "t4Mesh.spv");
// pub const t4Frag = ShaderInf.init(7, .frag, "taskTest/frag.slang", "t4Frag.spv");

// pub const gridTask = ShaderInf.init(8, .task, "gridTest/task.slang", "gridTask.spv");
// pub const gridMesh = ShaderInf.init(9, .mesh, "gridTest/mesh.slang", "gridMesh.spv");
// pub const gridFrag = ShaderInf.init(10, .frag, "gridTest/frag.slang", "gridFrag.spv");

// pub const indirectComp = ShaderInf.init(11, .comp, "indirectTest/comp.slang", "indirectComp.spv");
// pub const indirectTask = ShaderInf.init(12, .task, "indirectTest/task.slang", "indirectTask.spv");
// pub const indirectMesh = ShaderInf.init(13, .mesh, "indirectTest/mesh.slang", "indirectMesh.spv");
// pub const indirectFrag = ShaderInf.init(14, .frag, "indirectTest/frag.slang", "indirectFrag.spv");

// pub const shadersToCompile: []const ShaderInf = &.{
//     // t1Comp,
//     // t2Vert,
//     // t2Frag,
//     // t3Mesh,
//     // t3Frag,
//     // t4Task,
//     // t4Mesh,
//     // t4Frag,
//     // gridTask,
//     // gridMesh,
//     // gridFrag,
//     // indirectComp,
//     // indirectTask,
//     // indirectMesh,
//     // indirectFrag,
// };
