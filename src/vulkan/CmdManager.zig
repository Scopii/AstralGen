const std = @import("std");
const vk = @import("../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const Context = @import("Context.zig").Context;
const ResourceManager = @import("resources/ResourceManager.zig").ResourceManager;
const vh = @import("Helpers.zig");
const Command = @import("Command.zig").Command;

pub const CmdManager = struct {
    alloc: Allocator,
    gpi: vk.VkDevice,
    pool: vk.VkCommandPool,
    cmds: []Command,

    pub fn init(alloc: Allocator, context: *const Context, maxInFlight: u32) !CmdManager {
        const gpi = context.gpi;
        const pool = try createCmdPool(gpi, context.families.graphics);

        const cmds = try alloc.alloc(Command, maxInFlight);
        for (0..maxInFlight) |i| {
            cmds[i] = try Command.init(try createCmd(gpi, pool, vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY));
        }

        return .{
            .alloc = alloc,
            .gpi = gpi,
            .pool = pool,
            .cmds = cmds,
        };
    }

    pub fn deinit(self: *CmdManager) void {
        self.alloc.free(self.cmds);
        vk.vkDestroyCommandPool(self.gpi, self.pool, null);
    }

    pub fn getCmd(self: *CmdManager, flightId: u8) !Command {
        const cmd = self.cmds[flightId];
        try vh.check(vk.vkResetCommandBuffer(cmd.handle, 0), "could not reset command buffer"); // Might be optional
        return cmd;
    }
};

fn createCmd(gpi: vk.VkDevice, pool: vk.VkCommandPool, level: vk.VkCommandBufferLevel) !vk.VkCommandBuffer {
    const allocInf = vk.VkCommandBufferAllocateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = pool,
        .level = level,
        .commandBufferCount = 1,
    };
    var cmd: vk.VkCommandBuffer = undefined;
    try vh.check(vk.vkAllocateCommandBuffers(gpi, &allocInf, &cmd), "Could not create Cmd Buffer");
    return cmd;
}

fn createCmdPool(gpi: vk.VkDevice, familyIndex: u32) !vk.VkCommandPool {
    const poolInf = vk.VkCommandPoolCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT | vk.VK_COMMAND_POOL_CREATE_TRANSIENT_BIT,
        .queueFamilyIndex = familyIndex,
    };
    var pool: vk.VkCommandPool = undefined;
    try vh.check(vk.vkCreateCommandPool(gpi, &poolInf, null, &pool), "Could not create Cmd Pool");
    return pool;
}
