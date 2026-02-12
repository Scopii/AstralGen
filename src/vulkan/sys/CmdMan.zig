const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;
const rc = @import("../../configs/renderConfig.zig");
const Cmd = @import("../types/base/Cmd.zig").Cmd;
const Context = @import("Context.zig").Context;
const vk = @import("../../modules/vk.zig").c;
const vhF = @import("../help/Functions.zig");
const Allocator = std.mem.Allocator;
const std = @import("std");

pub const CmdMan = struct {
    alloc: Allocator,
    gpi: vk.VkDevice,
    cmdPool: vk.VkCommandPool,
    cmds: []Cmd,

    timestampPeriod: f32,

    pub fn init(alloc: Allocator, context: *const Context, maxInFlight: u8) !CmdMan {
        const gpi = context.gpi;
        const cmdPool = try createCmdPool(gpi, context.families.graphics);

        const cmds = try alloc.alloc(Cmd, maxInFlight);
        for (0..maxInFlight) |i| cmds[i] = try Cmd.init(cmdPool, vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY, gpi);

        var props: vk.VkPhysicalDeviceProperties = undefined;
        vk.vkGetPhysicalDeviceProperties(context.gpu, &props);

        return .{
            .alloc = alloc,
            .gpi = gpi,
            .cmdPool = cmdPool,
            .cmds = cmds,
            .timestampPeriod = props.limits.timestampPeriod,
        };
    }

    pub fn deinit(self: *CmdMan) void {
        for (self.cmds) |*cmd| cmd.deinit(self.gpi);
        self.alloc.free(self.cmds);
        vk.vkDestroyCommandPool(self.gpi, self.cmdPool, null);
    }

    pub fn getCmd(self: *CmdMan, flightId: u8) !*Cmd {
        const cmd = &self.cmds[flightId];
        try vhF.check(vk.vkResetCommandBuffer(cmd.handle, 0), "could not reset command buffer"); // Might be optional
        return cmd;
    }

    pub fn printQueryResults(self: *CmdMan, flightId: u8) !void {
        var cmd = self.cmds[flightId];
        try cmd.printQueryResults(self.gpi, self.timestampPeriod);
    }
};

fn createCmdPool(gpi: vk.VkDevice, familyIndex: u32) !vk.VkCommandPool {
    const poolInf = vk.VkCommandPoolCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT | vk.VK_COMMAND_POOL_CREATE_TRANSIENT_BIT,
        .queueFamilyIndex = familyIndex,
    };
    var pool: vk.VkCommandPool = undefined;
    try vhF.check(vk.vkCreateCommandPool(gpi, &poolInf, null, &pool), "Could not create Cmd Pool");
    return pool;
}
