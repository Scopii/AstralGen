const RenderRegistryData = @import("../../renderRegistry/RenderRegistryData.zig").RenderRegistryData;
const TexDesc = @import("../../render/types/res/TextureMeta.zig").TextureMeta.TexDesc;
const BufDesc = @import("../../render/types/res/BufferMeta.zig").BufferMeta.BufDesc;
const GroupChange = @import("../../renderGraph/components.zig").GroupChange;
const ResDesc = @import("../../renderGraph/components.zig").ResDesc;
const rc = @import("../../.configs/renderConfig.zig");
const std = @import("std");

const getResTyp = @import("../../renderGraph/components.zig").getResTyp;

const MapperData = @import("../5.1_Mapper/MapperData.zig").MapperData;
const ComparatorData = @import("ComparatorData.zig").ComparatorData;

// Step 6

pub const ComparatorSys = struct {
    pub fn build(comparatorData: *ComparatorData, mapperData: *const MapperData, registry: *const RenderRegistryData) !void {
        comparatorData.persistentChanges.clear();

        for (mapperData.persistentGroups.getConstItems(), 0..) |newGroupInf, i| {
            const groupRootId = mapperData.persistentGroups.getKeyByIndex(@intCast(i));

            if (mapperData.prevPersistentGroups.isKeyUsed(groupRootId) == false) {
                comparatorData.persistentChanges.appendAssumeCapacity(.{ .rootResource = groupRootId, .change = .created });
                continue;
            }

            const lastGroupInf = mapperData.prevPersistentGroups.getByKey(groupRootId);
            const newPass = lastGroupInf.rootPass != newGroupInf.rootPass;
            const sameDesc = resDescEqual(&lastGroupInf.desc, &newGroupInf.desc);

            const change: GroupChange.ResUpdate = switch (sameDesc) {
                true => if (newPass == false) .unchanged else .newPass,
                false => if (newPass == false) .newDesc else .newPassAndDesc,
            };
            comparatorData.persistentChanges.appendAssumeCapacity(.{ .rootResource = groupRootId, .change = change });
        }

        for (0..mapperData.prevPersistentGroups.getLength()) |i| {
            const groupRootId = mapperData.prevPersistentGroups.getKeyByIndex(@intCast(i));
            if (mapperData.persistentGroups.isKeyUsed(groupRootId) == false) {
                comparatorData.persistentChanges.appendAssumeCapacity(.{ .rootResource = groupRootId, .change = .deleted });
            }
        }

        // Debug
        if (rc.FRAME_GRAPH_DEBUG) {
            std.debug.print("5.3.MappingComparator: \n", .{});
            for (comparatorData.persistentChanges.constSlice()) |groupChange| {
                const groupRootName = try registry.getResourceName(groupChange.rootResource);
                std.debug.print("- Persistent {s} {s}: {s}\n", .{ @tagName(getResTyp(groupChange.rootResource)), groupRootName, @tagName(groupChange.change) });
            }
            std.debug.print("\n", .{});
        }
    }
};

fn resDescEqual(desc1: *const ResDesc, desc2: *const ResDesc) bool {
    return switch (desc1.*) {
        .bufDesc => |bufDesc| bufDescEqual(&bufDesc, &desc2.bufDesc),
        .texDesc => |texDesc| texDescEqual(&texDesc, &desc2.texDesc),
    };
}

fn bufDescEqual(bufDesc1: *const BufDesc, bufDesc2: *const BufDesc) bool {
    return std.meta.eql(bufDesc1.*, bufDesc2.*);
}

fn texDescEqual(texDesc1: *const TexDesc, texDesc2: *const TexDesc) bool {
    return std.meta.eql(texDesc1.*, texDesc2.*);
}
