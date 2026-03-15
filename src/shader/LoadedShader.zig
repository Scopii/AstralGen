pub const ShaderInf = @import("../shader/ShaderInf.zig").ShaderInf;

pub const LoadedShader = struct {
    pub const alignedShader = []align(@alignOf(u32)) u8;
    data: []align(@alignOf(u32)) u8,
    timeStamp: i128,
    shaderInf: ShaderInf,
};