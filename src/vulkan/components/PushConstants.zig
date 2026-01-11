const ResourceManager = @import("../systems/ResourceManager.zig").ResourceManager;
const FrameData = @import("../../App.zig").FrameData;
const Pass = @import("../components/Pass.zig").Pass;
const std = @import("std");

pub const PushConstants = extern struct {
    runTime: f32 = 0,
    deltaTime: f32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    resourceSlots: [14]ResourceSlot = undefined,

    pub const ResourceSlot = extern struct {
        index: u32 = 0,
        count: u32 = 0,
    };

    pub fn init(resMan: *ResourceManager, pass: Pass, frameData: FrameData) !PushConstants {
        var pcs = PushConstants{ .runTime = frameData.runTime, .deltaTime = frameData.deltaTime };

        var mask: [14]bool = .{false} ** 14;
        var resourceSlots: [14]ResourceSlot = undefined;

        for (pass.bufUses) |bufUse| {
            const shaderSlot = bufUse.shaderSlot;

            if (shaderSlot) |slot| {
                if (mask[slot.val] == false) {
                    resourceSlots[slot.val] = try resMan.getBufferResourceSlot(bufUse.bufId);
                    mask[slot.val] = true;
                } else std.debug.print("Pass Shader Slot {} already used\n", .{slot.val});
            }
        }

        for (pass.texUses) |texUse| {
            const shaderSlot = texUse.shaderSlot;

            if (shaderSlot) |slot| {
                if (mask[slot.val] == false) {
                    resourceSlots[slot.val] = try resMan.getTextureResourceSlot(texUse.texId);
                    mask[slot.val] = true;
                } else std.debug.print("Pass Shader Slot {} already used\n", .{slot.val});
            }
        }

        pcs.resourceSlots = resourceSlots;

        const mainTexId = pass.getMainTexId();
        if (mainTexId) |texId| {
            const mainTex = try resMan.getTexturePtr(texId);
            pcs.width = mainTex.base.extent.width;
            pcs.height = mainTex.base.extent.height;
        }

        return pcs;
    }
};
