const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const config = @import("../config.zig");
const Context = @import("Context.zig").Context;
const RenderType = @import("../config.zig").RenderType;
const ShaderLayout = @import("../config.zig").ShaderLayout;
const ResourceManager = @import("ResourceManager.zig").ResourceManager;
const CreateMapArray = @import("../structures/MapArray.zig").CreateMapArray;
const LoadedShader = @import("../core/ShaderCompiler.zig").LoadedShader;
const check = @import("error.zig").check;
const ShaderObject = @import("ShaderObject.zig").ShaderObject;
const ShaderObject2 = @import("ShaderObject.zig").ShaderObject2;
const ShaderStage = @import("ShaderObject.zig").ShaderStage;
const ztracy = @import("ztracy");

const Pass = struct {
    renderType: RenderType,
    renderImgId: u8,
    shaderIds: [8]u8,
};

pub const PassManager = struct {
    alloc: Allocator,
    passes: std.ArrayList(Pass),

    pub fn init(alloc: Allocator) !PassManager {
        return .{
            .alloc = alloc,
            .passes = std.ArrayList(Pass).init(alloc),
        };
    }

    // pub fn createPasses(self: *PassManager, shaderLayout: []config.PassConfig) void {
    //     for (shaderLayout) |shaderLayout| {
    //         const renderType = checkShaderLayout();
    //         self.passes.append(Pass{.renderType = renderType, .});
    //     }
    // }

    // pub fn validatePass(self: *PassManager, shaderLayout: []ShaderLayout) void {
    //     for (shaderLayout) |shaderLayout| {
    //         const renderType = checkShaderLayout();
    //         self.passes.append(Pass{.renderType = renderType, .});
    //     }
    // }
};

fn checkShaderLayout(shaderLayout: ShaderLayout) !RenderType {
    var shdr: [9]u8 = .{0} ** 9;
    var prevIndex: i8 = -1;

    for (shaderLayout.shaders) |shader| {
        const curIndex: i8 = switch (shader.shaderType) {
            .compute => 0,
            .vert => 1,
            // .tessControl => 2,
            // .tessEval => 3,
            // .geometry => 4,
            .task => 5,
            .mesh => 6,
            .frag => 7,
            .meshNoTask => 6, // NOT CHECKED YET
        };
        if (curIndex <= prevIndex) return error.ShaderLayoutOrderInvalid;
        prevIndex = curIndex;
        shdr[@intCast(curIndex)] += 1;
    }
    switch (shaderLayout.shaders.len) {
        1 => if (shdr[0] == 1) return .computePass else if (shdr[1] == 1) return .vertexPass,
        2 => if (shdr[6] == 1 and shdr[7] == 1) return .meshPass,
        3 => if (shdr[5] == 1 and shdr[6] == 1 and shdr[7] == 1) return .taskMeshPass,
        else => {},
    }
    if (shdr[1] == 1 and shdr[2] <= 1 and shdr[3] <= 1 and shdr[4] <= 1 and shdr[5] == 0 and shdr[6] == 0 and shdr[7] == 1) return .graphicsPass;
    if (shdr[2] != shdr[3]) return error.ShaderLayoutTessellationMismatch;
    return error.ShaderLayoutInvalid;
}
