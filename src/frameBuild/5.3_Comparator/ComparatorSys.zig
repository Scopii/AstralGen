const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const GroupChange = @import("../../frameBuild/components.zig").GroupChange;
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
        comparatorData.persistentChanges.clear();

        // Buffer Changes
        for (mapperData.bufGroupsPersistent.getConstItems(), 0..) |newGroupInf, i| {
            const groupRootId = mapperData.bufGroupsPersistent.getKeyByIndex(@intCast(i));
            const isGroupInLast = mapperData.lastBufGroupsPersistent.isKeyUsed(groupRootId);

            if (isGroupInLast == true) {
                const lastGroupInf = mapperData.lastBufGroupsPersistent.getByKey(groupRootId);
                const newDesc = !bufDescEqual(&lastGroupInf.bufDesc, &newGroupInf.bufDesc);
                const newPass = lastGroupInf.rootPass != newGroupInf.rootPass;

                const change: GroupChange.ResUpdate = switch (newDesc) {
                    false => if (newPass == false) .unchanged else .newPass,
                    true => if (newPass == false) .newDesc else .newPassAndDesc,
                };
                comparatorData.persistentChanges.appendAssumeCapacity(GroupChange{ .rootResource = .{ .bufPassId = groupRootId }, .change = change });
            } else {
                comparatorData.persistentChanges.appendAssumeCapacity(GroupChange{ .rootResource = .{ .bufPassId = groupRootId }, .change = .created });
            }
        }

        for (0..mapperData.lastBufGroupsPersistent.getLength()) |i| {
            const groupRootId = mapperData.lastBufGroupsPersistent.getKeyByIndex(@intCast(i));
            const isGroupInNew = mapperData.bufGroupsPersistent.isKeyUsed(groupRootId);
            if (isGroupInNew == false) comparatorData.persistentChanges.appendAssumeCapacity(GroupChange{ .rootResource = .{ .bufPassId = groupRootId }, .change = .deleted });
        }

        // Texture Changes
        for (mapperData.texGroupsPersistent.getConstItems(), 0..) |newGroupInf, i| {
            const groupRootId = mapperData.texGroupsPersistent.getKeyByIndex(@intCast(i));
            const isGroupInLast = mapperData.lastTexGroupsPersistent.isKeyUsed(groupRootId);

            if (isGroupInLast == true) {
                const lastGroupInf = mapperData.lastTexGroupsPersistent.getByKey(groupRootId);
                const newDesc = !texDescEqual(&lastGroupInf.texDesc, &newGroupInf.texDesc);
                const newPass = lastGroupInf.rootPass != newGroupInf.rootPass;

                const change: GroupChange.ResUpdate = switch (newDesc) {
                    false => if (newPass == false) .unchanged else .newPass,
                    true => if (newPass == false) .newDesc else .newPassAndDesc,
                };
                comparatorData.persistentChanges.appendAssumeCapacity(GroupChange{ .rootResource = .{ .texPassId = groupRootId }, .change = change });
            } else {
                comparatorData.persistentChanges.appendAssumeCapacity(GroupChange{ .rootResource = .{ .texPassId = groupRootId }, .change = .created });
            }
        }

        for (0..mapperData.lastTexGroupsPersistent.getLength()) |i| {
            const groupRootId = mapperData.lastTexGroupsPersistent.getKeyByIndex(@intCast(i));
            const isGroupInNew = mapperData.texGroupsPersistent.isKeyUsed(groupRootId);
            if (isGroupInNew == false) comparatorData.persistentChanges.appendAssumeCapacity(GroupChange{ .rootResource = .{ .texPassId = groupRootId }, .change = .deleted });
        }

        // Debug Output
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.3.MappingComparator: \n", .{});
            for (comparatorData.persistentChanges.constSlice()) |groupChange| {
                const groupRootName = switch (groupChange.rootResource) {
                    .bufPassId => |id| try registryData.getBufferName(id),
                    .texPassId => |id| try registryData.getTextureName(id),
                };
                std.debug.print("- Persistent {s} {s}: {s}\n", .{ @tagName(groupChange.rootResource), groupRootName, @tagName(groupChange.change) });
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
