const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const TexGroupChange = @import("../../frameBuild/components.zig").TexGroupChange;
const BufGroupChange = @import("../../frameBuild/components.zig").BufGroupChange;
const TexPassId = @import("../../.configs/idConfig.zig").TexPassId;
const BufPassId = @import("../../.configs/idConfig.zig").BufPassId;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const RegistryData = @import("../0_Registry/RegistryData.zig").RegistryData;
const MapperData = @import("../5.1_Mapper/MapperData.zig").MapperData;
const ComparatorData = @import("ComparatorData.zig").ComparatorData;

// Step 6

pub const ComparatorSys = struct {
    pub fn buildChanges(comparatorData: *ComparatorData, mapperData: *const MapperData, registryData: *const RegistryData) !void {
        comparatorData.persistentBufChanges.clear();
        comparatorData.persistentTexChanges.clear();

        // Buffer Changes
        for (mapperData.bufGroupsPersistent.getConstItems(), 0..) |newGroupInf, i| {
            const groupRootId = mapperData.bufGroupsPersistent.getKeyByIndex(@intCast(i));
            const isGroupInLast = mapperData.lastBufGroupsPersistent.isKeyUsed(groupRootId);

            if (isGroupInLast == true) {
                const lastGroupInf = mapperData.lastBufGroupsPersistent.getByKey(groupRootId);
                const newDesc = !bufDescEqual(&lastGroupInf.bufDesc, &newGroupInf.bufDesc);
                const newPass = lastGroupInf.rootPass != newGroupInf.rootPass;

                const change: BufGroupChange.GroupChange = switch (newDesc) {
                    false => if (newPass == false) .unchanged else .newPass,
                    true => if (newPass == false) .newDesc else .newPassAndDesc,
                };
                comparatorData.persistentBufChanges.appendAssumeCapacity(BufGroupChange{ .rootBuf = groupRootId, .change = change });
            } else {
                comparatorData.persistentBufChanges.appendAssumeCapacity(BufGroupChange{ .rootBuf = groupRootId, .change = .created });
            }
        }

        for (0..mapperData.lastBufGroupsPersistent.getLength()) |i| {
            const groupRootId = mapperData.lastBufGroupsPersistent.getKeyByIndex(@intCast(i));
            const isGroupInNew = mapperData.bufGroupsPersistent.isKeyUsed(groupRootId);
            if (isGroupInNew == false) comparatorData.persistentBufChanges.appendAssumeCapacity(BufGroupChange{ .rootBuf = groupRootId, .change = .deleted });
        }

        // Texture Changes
        for (mapperData.texGroupsPersistent.getConstItems(), 0..) |newGroupInf, i| {
            const groupRootId = mapperData.texGroupsPersistent.getKeyByIndex(@intCast(i));
            const isGroupInLast = mapperData.lastTexGroupsPersistent.isKeyUsed(groupRootId);

            if (isGroupInLast == true) {
                const lastGroupInf = mapperData.lastTexGroupsPersistent.getByKey(groupRootId);
                const newDesc = !texDescEqual(&lastGroupInf.texDesc, &newGroupInf.texDesc);
                const newPass = lastGroupInf.rootPass != newGroupInf.rootPass;

                const change: TexGroupChange.GroupChange = switch (newDesc) {
                    false => if (newPass == false) .unchanged else .newPass,
                    true => if (newPass == false) .newDesc else .newPassAndDesc,
                };
                comparatorData.persistentTexChanges.appendAssumeCapacity(TexGroupChange{ .rootTex = groupRootId, .change = change });
            } else {
                comparatorData.persistentTexChanges.appendAssumeCapacity(TexGroupChange{ .rootTex = groupRootId, .change = .created });
            }
        }

        for (0..mapperData.lastTexGroupsPersistent.getLength()) |i| {
            const groupRootId = mapperData.lastTexGroupsPersistent.getKeyByIndex(@intCast(i));
            const isGroupInNew = mapperData.texGroupsPersistent.isKeyUsed(groupRootId);
            if (isGroupInNew == false) comparatorData.persistentTexChanges.appendAssumeCapacity(TexGroupChange{ .rootTex = groupRootId, .change = .deleted });
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.3.MappingComparator: \n", .{});
            for (comparatorData.persistentBufChanges.constSlice()) |bufGroupChange| {
                const rootBuf = try registryData.getBufferName(bufGroupChange.rootBuf);
                std.debug.print("- Persistent BufGroup {s}: {s}\n", .{ rootBuf, @tagName(bufGroupChange.change) });
            }
            for (comparatorData.persistentTexChanges.constSlice()) |texGroupChange| {
                const rootTex = try registryData.getTextureName(texGroupChange.rootTex);
                std.debug.print("- Persistent TexGroup {s}: {s}\n", .{ rootTex, @tagName(texGroupChange.change) });
            }
            std.debug.print("\n", .{});
        }
    }
};

fn bufDescEqual(bufDesc1: *const BufDesc, bufDesc2: *const BufDesc) bool {
    return std.meta.eql(bufDesc1.*, bufDesc2.*);
}

fn texDescEqual(texDesc1: *const TexDesc, texDesc2: *const TexDesc) bool {
    return std.meta.eql(texDesc1.*, texDesc2.*);
}
