const std = @import("std");
const vk = @import("../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const shaderCon = @import("../configs/shaderConfig.zig");
const Context = @import("Context.zig").Context;
const ResourceManager = @import("resources/ResourceManager.zig").ResourceManager;
const CreateMapArray = @import("../structures/MapArray.zig").CreateMapArray;
const LoadedShader = @import("../core/ShaderCompiler.zig").LoadedShader;
const ShaderObject = @import("ShaderObject.zig").ShaderObject;
const Pass = @import("Pass.zig").Pass;

pub const ShaderManager = struct {
    alloc: Allocator,
    descLayout: vk.VkDescriptorSetLayout,
    gpi: vk.VkDevice,
    shaders: CreateMapArray(ShaderObject, shaderCon.SHADER_MAX, u8, shaderCon.SHADER_MAX, 0) = .{},

    pub fn init(alloc: Allocator, context: *const Context, resourceManager: *const ResourceManager) !ShaderManager {
        return .{
            .alloc = alloc,
            .descLayout = resourceManager.descMan.descLayout,
            .gpi = context.gpi,
        };
    }

    pub fn deinit(self: *ShaderManager) void {
        const gpi = self.gpi;
        for (self.shaders.getElements()) |*shader| {
            shader.deinit(gpi);
        }
    }

    pub fn isShaderIdUsed(self: *ShaderManager, shaderId: u8) bool {
        return self.shaders.isKeyUsed(shaderId);
    }

    pub fn createShaders(self: *ShaderManager, loadedShaders: []LoadedShader) !void {
        for (loadedShaders) |loadedShader| {
            const shaderObj = try ShaderObject.init(self.gpi, loadedShader, self.descLayout);
            const id = loadedShader.shaderInf.id.val;

            if (self.shaders.isKeyUsed(id) == true) {
                self.shaders.getPtr(id).*.deinit(self.gpi);
                std.debug.print("Shader {} Updated\n", .{id});
            } else std.debug.print("Shader {} Created\n", .{id});
            self.shaders.set(id, shaderObj);
        }
    }

    pub fn getShaders(self: *ShaderManager, shaderIds: []const shaderCon.ShaderInf.ShaderId) [8]ShaderObject {
        var shaders: [8]ShaderObject = undefined;
        for (0..shaderIds.len) |i| {
            shaders[i] = self.shaders.get(shaderIds[i].val);
        }
        return shaders;
    }

    pub fn isPassValid(self: *ShaderManager, pass: Pass) bool {
        const shaders = self.getShaders(pass.shaderIds)[0..pass.shaderIds.len];

        const passType = checkShaderLayout(shaders) catch |err| {
            std.debug.print("Pass {} Shader Layout invalid", .{err});
            return false;
        };
        const passKind = pass.passTyp;

        switch (passType) {
            .computePass => if (passKind != .compute and passKind != .computeOnTex) return false,
            .graphicsPass, .vertexPass => if (passKind != .graphics) return false,
            .taskMeshPass, .meshPass => if (passKind != .taskOrMesh) return false,
        }
        return true;
    }
};

fn checkShaderLayout(shaders: []const ShaderObject) !enum { computePass, graphicsPass, meshPass, taskMeshPass, vertexPass } {
    var shdr: [9]u8 = .{0} ** 9;
    var prevIndex: i8 = -1;

    for (shaders) |shader| {
        const curIndex: i8 = switch (shader.stage) {
            .compute => 0,
            .vert => 1,
            .tessControl => 2,
            .tessEval => 3,
            .geometry => 4,
            .task => 5,
            .mesh => 6,
            .meshNoTask => 6,
            .frag => 7,
        };
        prevIndex = curIndex;
        shdr[@intCast(curIndex)] += 1;
    }
    switch (shaders.len) {
        1 => if (shdr[0] == 1) return .computePass else if (shdr[1] == 1) return .vertexPass,
        2 => if (shdr[6] == 1 and shdr[7] == 1) return .meshPass,
        3 => if (shdr[5] == 1 and shdr[6] == 1 and shdr[7] == 1) return .taskMeshPass,
        else => {},
    }
    if (shdr[1] == 1 and shdr[2] <= 1 and shdr[3] <= 1 and shdr[4] <= 1 and shdr[5] == 0 and shdr[6] == 0 and shdr[7] == 1) return .graphicsPass;
    if (shdr[2] != shdr[3]) return error.ShaderLayoutTessellationMismatch;
    return error.ShaderLayoutInvalid;
}
