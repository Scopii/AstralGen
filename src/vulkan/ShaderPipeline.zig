const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const config = @import("../config.zig");
const ShaderObject = @import("ShaderObject.zig").ShaderObject;
const check = @import("error.zig").check;
const joinPath = @import("../core/FileManager.zig").joinPath;
const resolveProjectRoot = @import("../core/FileManager.zig").resolveProjectRoot;

pub const RenderType = enum { compute, graphics, mesh };
pub const RenderPass = enum { compute1, compute2, graphics1, graphics2, mesh1, mesh2 };

pub const ShaderInfo = struct {
    renderType: RenderType,
    renderPass: RenderPass,
    stage: c.VkShaderStageFlagBits,
    glslFile: []const u8,
    spvFile: []const u8,
};

pub const ShaderPipeline = struct {
    pipeInf: []const ShaderInfo,
    shaderObjects: std.ArrayList(ShaderObject),

    pub fn init(alloc: Allocator, gpi: c.VkDevice, pipeInfos: []const ShaderInfo, descLayout: c.VkDescriptorSetLayout, renderType: RenderType) !ShaderPipeline {
        if (renderType == .compute and pipeInfos.len > 1) {
            std.log.err("ShaderPipeline: Compute only supports 1 Stage", .{});
            return error.ShaderStageOverflow;
        }

        var shaderObjects = std.ArrayList(ShaderObject).init(alloc);

        for (0..pipeInfos.len) |i| {
            const pipeInf = pipeInfos[i];
            const nextStage = if (i + 1 <= pipeInfos.len - 1) pipeInfos[i + 1].stage else 0;
            const shaderObj = try ShaderObject.init(gpi, pipeInf, nextStage, alloc, descLayout, renderType);
            shaderObjects.append(shaderObj) catch |err| {
                std.debug.print("ShaderPipeline: Could not append ShaderObject, err {}\n", .{err});
                return error.ShaderAppend;
            };
        }

        return .{
            .pipeInf = pipeInfos,
            .shaderObjects = shaderObjects,
        };
    }

    pub fn deinit(self: *ShaderPipeline, gpi: c.VkDevice) void {
        for (self.shaderObjects.items) |*shaderObject| shaderObject.deinit(gpi);
        self.shaderObjects.deinit();
    }
};
