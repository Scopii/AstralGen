const ResourceMan = @import("../../sys/ResourceMan.zig").ResourceMan;
const FrameData = @import("../../../App.zig").FrameData;
const BufferUse = @import("../pass/BufferUse.zig").BufferUse;
const TextureUse = @import("../pass/TextureUse.zig").TextureUse;
const TexId = @import("TextureMeta.zig").TextureMeta.TexId;
const std = @import("std");

pub const PushData = extern struct {
    runTime: f32 = 0,
    deltaTime: f32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    resourceSlots: [14]u32 = undefined,

    pub fn init(resMan: *ResourceMan, bufUses: []const BufferUse, texUses: []const TextureUse, mainTexId: ?TexId, frameData: FrameData, flightId: u8) !PushData {
        var pcs = PushData{ .runTime = frameData.runTime, .deltaTime = frameData.deltaTime };
        var mask: [14]bool = .{false} ** 14;

        for (bufUses) |bufUse| {
            const shaderSlot = bufUse.shaderSlot;

            if (shaderSlot) |slot| {
                if (mask[slot] == false) {
                    pcs.resourceSlots[slot] = try resMan.getDescriptor(bufUse.bufId, flightId);
                    mask[slot] = true;
                } else std.debug.print("Pass Shader Slot {} already used\n", .{slot});
            }
        }

        for (texUses) |texUse| {
            const shaderSlot = texUse.shaderSlot;

            if (shaderSlot) |slot| {
                if (mask[slot] == false) {
                    pcs.resourceSlots[slot] = try resMan.getDescriptor(texUse.texId, flightId);
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
