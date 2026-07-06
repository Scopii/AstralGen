const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const getResTyp = @import("../../frameBuild/components.zig").getResTyp;
const resToBuf = @import("../../frameBuild/components.zig").resToBuf;
const resToTex = @import("../../frameBuild/components.zig").resToTex;
const texToRes = @import("../../frameBuild/components.zig").texToRes;
const bufToRes = @import("../../frameBuild/components.zig").bufToRes;

const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const PassData = @import("../1_Pass/PassData.zig").PassData;
const AccessData = @import("../1.5_Access/AccessData.zig").AccessData;
const ResourceData = @import("ResourceData.zig").ResourceData;

// Step 2

pub const ResourceSys = struct {
    pub fn build(resourceData: *ResourceData, accessData: *const AccessData, passData: *const PassData, registryData: *const RegistryData) !void {
        resourceData.bufDescs.clear();
        resourceData.texDescs.clear();
        resourceData.memSizes.clear();

        for (accessData.accesses.constSlice()) |access| {
            switch (getResTyp(access.input)) {
                .Buf => {
                    const inputBuf = resToBuf(access.input);
                    if (resourceData.bufDescs.isKeyUsed(inputBuf) == false) {
                        const desc1 = try registryData.getBufferDefinition(inputBuf);
                        resourceData.bufDescs.upsert(inputBuf, desc1);
                    }

                    if (access.output) |output| {
                        const outputBuf = resToBuf(output);
                        if (resourceData.bufDescs.isKeyUsed(outputBuf) == false) {
                            const desc2 = try registryData.getBufferDefinition(outputBuf);
                            resourceData.bufDescs.upsert(outputBuf, desc2);
                        }
                    }
                },
                .Tex => {
                    const passExtent = passData.passExtents.getByKey(access.pass);
                    const isWrite = (access.access == .write or access.output != null);
                    const resize = isWrite or rc.PASS_TEXTURE_RESIZE_INCLUDES_READ;

                    // For Input
                    const inputTex = resToTex(access.input);
                    if (resourceData.texDescs.isKeyUsed(inputTex) == false) {
                        var desc1 = try registryData.getTextureDefinition(inputTex);
                        if (desc1.fitPass == true) { // no resize?
                            desc1.width = 0;
                            desc1.height = 0;
                        }
                        resourceData.texDescs.upsert(inputTex, desc1);
                    }

                    var desc1 = resourceData.texDescs.getPtrByKey(inputTex);
                    if (desc1.fitPass == true and resize) {
                        desc1.width = @max(desc1.width, passExtent.width);
                        desc1.height = @max(desc1.height, passExtent.height);
                    }

                    // For Output
                    if (access.output) |output| {
                        const outputTex = resToTex(output);

                        if (resourceData.texDescs.isKeyUsed(outputTex) == false) {
                            var desc2 = try registryData.getTextureDefinition(outputTex);
                            if (desc2.fitPass == true) {
                                desc2.width = 0;
                                desc2.height = 0;
                            }
                            resourceData.texDescs.upsert(outputTex, desc2);
                        }

                        var desc2 = resourceData.texDescs.getPtrByKey(outputTex);
                        if (desc2.fitPass == true and resize) {
                            desc2.width = @max(desc2.width, passExtent.width);
                            desc2.height = @max(desc2.height, passExtent.height);
                        }
                    }
                },
            }
        }

        // If Description is Share = Transient add memSize
        for (resourceData.bufDescs.getConstItems(), 0..) |bufDesc, i| {
            const bufKey = resourceData.bufDescs.getKeyByIndex(@intCast(i));
            if (bufDesc.share == .transient) resourceData.memSizes.upsert(bufToRes(bufKey), bufDesc.guessMemoryCost());
        }
        for (resourceData.texDescs.getConstItems(), 0..) |texDesc, i| {
            const texKey = resourceData.texDescs.getKeyByIndex(@intCast(i));
            if (texDesc.share == .transient) resourceData.memSizes.upsert(texToRes(texKey), texDesc.guessMemoryCost());
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("2.ResourceExtractor: \n", .{});
            for (resourceData.memSizes.getConstItems(), 0..) |memSize, i| {
                const resPassId = resourceData.memSizes.getKeyByIndex(@intCast(i));
                const resTyp = getResTyp(resPassId);
                const resName = try registryData.getResourceName(resPassId);
                std.debug.print(" {}. {s} ({s}) -> Mem {} Bytes\n", .{ i, @tagName(resTyp), resName, memSize });
            }
            std.debug.print("\n", .{});
        }
    }
};
