const TextureAssignments = @import("../../../frameBuild/6_resourceAssigner/ResourceAssignerData.zig").ResourceAssignerData.TextureAssignments;
const BufferAssignments = @import("../../../frameBuild/6_resourceAssigner/ResourceAssignerData.zig").ResourceAssignerData.BufferAssignments;
const TextureEnum = @import("../../../frameBuild/enums.zig").TextureEnum;
const BufferEnum = @import("../../../frameBuild/enums.zig").BufferEnum;
const ResourceMan = @import("../../sys/ResourceMan.zig").ResourceMan;
const BufferUse = @import("../pass/BufferUse.zig").BufferUse;
const TextureUse = @import("../pass/TextureUse.zig").TextureUse;
const TexId = @import("TextureMeta.zig").TextureMeta.TexId;
const BufId = @import("BufferMeta.zig").BufferMeta.BufId;
const FrameData = @import("../../../App.zig").FrameData;
const std = @import("std");

pub const PushData = extern struct {
    runTime: f32 = 0,
    deltaTime: f32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    resourceSlots: [14]u32 = undefined,

    pub fn init(
        resMan: *ResourceMan,
        bufUses: []const BufferUse,
        texUses: []const TextureUse,
        mainTexId: ?TexId,
        frameData: FrameData,
        flightId: u8,
        bufAssigns: *const BufferAssignments,
        texAssigns: *const TextureAssignments,
    ) !PushData {
        var pcs = PushData{ .runTime = frameData.runTime, .deltaTime = frameData.deltaTime };
        var mask: [14]bool = .{false} ** 14;

        for (bufUses) |bufUse| {
            const shaderSlot = bufUse.shaderSlot;

            if (shaderSlot) |slot| {
                if (mask[slot] == false) {
                    const bufId = try resolveBuffer(bufUse.bufLink.in, bufAssigns);
                    pcs.resourceSlots[slot] = try resMan.getBufferDescriptor(bufId, flightId);
                    mask[slot] = true;
                } else std.debug.print("Pass Shader Slot {} already used\n", .{slot});
            }
        }

        for (texUses) |texUse| {
            const shaderSlot = texUse.shaderSlot;

            if (shaderSlot) |slot| {
                if (mask[slot] == false) {
                    const texId = try resolveTexture(texUse.texLink.in, texAssigns);
                    pcs.resourceSlots[slot] = try resMan.getTextureDescriptor(texId, flightId, texUse.descUse);
                    mask[slot] = true;
                } else std.debug.print("Pass Shader Slot {} already used\n", .{slot});
            }
        }

        if (mainTexId) |texId| {
            const mainTex = try resMan.get(texId, flightId);
            pcs.width = mainTex.extent.width;
            pcs.height = mainTex.extent.height;
        }

        return pcs;
    }
};

fn resolveTexture(texEnum: TextureEnum, texAssigns: *const TextureAssignments) !TexId {
    if (texAssigns.isKeyUsed(@intFromEnum(texEnum)) == true) return texAssigns.getByKey(@intFromEnum(texEnum)) else {
        std.debug.print("Error: Texture {s} not assigned\n", .{@tagName(texEnum)});
        return error.TextureNotAssigned;
    }
}

fn resolveBuffer(bufEnum: BufferEnum, bufAssigns: *const BufferAssignments) !BufId {
    if (bufAssigns.isKeyUsed(@intFromEnum(bufEnum)) == true) return bufAssigns.getByKey(@intFromEnum(bufEnum)) else {
        std.debug.print("Error: Buffer {s} not assigned\n", .{@tagName(bufEnum)});
        return error.BufferNotAssigned;
    }
}
