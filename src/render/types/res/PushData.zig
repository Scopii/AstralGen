const TextureAssignments = @import("../../../frameBuild/6_resourceAssigner/ResourceAssignerData.zig").ResourceAssignerData.TextureAssignments;
const BufferAssignments = @import("../../../frameBuild/6_resourceAssigner/ResourceAssignerData.zig").ResourceAssignerData.BufferAssignments;
const TexPassId = @import("../../../frameBuild/components.zig").TexPassId;
const BufPassId = @import("../../../frameBuild/components.zig").BufPassId;
const ResourceMan = @import("../../sys/ResourceMan.zig").ResourceMan;
const TextureFill = @import("../pass/TextureFill.zig").TextureFill;
const BufferFill = @import("../pass/BufferFill.zig").BufferFill;
const TexId = @import("../../../.configs/idConfig.zig").TexId;
const BufId = @import("BufferMeta.zig").BufferMeta.BufId;
const FrameData = @import("../../../App.zig").FrameData;
const std = @import("std");

pub const PushData = extern struct {
    runTime: f32 = 0,
    deltaTime: f32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    resourceSlots: [14]u32 = undefined,

    pub fn init(resMan: *ResourceMan, bufUses: []const BufferFill, texUses: []const TextureFill, mainTexId: ?TexId, frameData: FrameData, flightId: u8) !PushData {
        var pcs = PushData{ .runTime = frameData.runTime, .deltaTime = frameData.deltaTime };
        var mask: [14]bool = .{false} ** 14;

        for (bufUses) |bufUse| {
            const shaderSlot = bufUse.shaderSlot;

            if (shaderSlot) |slot| {
                if (mask[slot] == false) {
                    pcs.resourceSlots[slot] = try resMan.getBufferDescriptor(bufUse.bufId, flightId);
                    mask[slot] = true;
                } else std.debug.print("Pass Shader Slot {} already used\n", .{slot});
            }
        }

        for (texUses) |texUse| {
            const shaderSlot = texUse.shaderSlot;

            if (shaderSlot) |slot| {
                if (mask[slot] == false) {
                    pcs.resourceSlots[slot] = try resMan.getTextureDescriptor(texUse.texId, flightId, texUse.descUse);
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
