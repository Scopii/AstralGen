const ResourceMan = @import("../../sys/ResourceMan.zig").ResourceMan;
const FrameData = @import("../../../App.zig").FrameData;
const Pass = @import("../../types/base/Pass.zig").Pass;
const std = @import("std");

pub const PushData = extern struct {
    runTime: f32 = 0,
    deltaTime: f32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    resourceSlots: [14]u32 = undefined,

    pub fn init(resMan: *ResourceMan, pass: Pass, frameData: FrameData, flightId: u8) !PushData {
        var pcs = PushData{ .runTime = frameData.runTime, .deltaTime = frameData.deltaTime };
        var mask: [14]bool = .{false} ** 14;

        for (pass.bufUses) |bufUse| {
            const shaderSlot = bufUse.shaderSlot;

            if (shaderSlot) |slot| {
                if (mask[slot] == false) {
                    pcs.resourceSlots[slot] = try resMan.getBufferResourceSlot(bufUse.bufId, flightId);
                    mask[slot] = true;
                } else std.debug.print("Pass Shader Slot {} already used\n", .{slot});
            }
        }

        for (pass.texUses) |texUse| {
            const shaderSlot = texUse.shaderSlot;

            if (shaderSlot) |slot| {
                if (mask[slot] == false) {
                    pcs.resourceSlots[slot] = try resMan.getTextureResourceSlot(texUse.texId, flightId);
                    mask[slot] = true;
                } else std.debug.print("Pass Shader Slot {} already used\n", .{slot});
            }
        }

        const mainTexId = pass.getMainTexId();
        if (mainTexId) |texId| {
            const mainTex = try resMan.getTex(texId, flightId);
            pcs.width = mainTex.extent.width;
            pcs.height = mainTex.extent.height;
        }

        return pcs;
    }
};
