const CreateMapArray = @import("../../structures/MapArray.zig").CreateMapArray;
const Command = @import("../components/Command.zig").Command;
const Context = @import("Context.zig").Context;
const vk = @import("../../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const vh = @import("Helpers.zig");
const std = @import("std");

pub const Query = struct {
    name: []const u8,
    startQueryIndex: u32 = 0,
    endQueryIndex: u32 = 0,
};

pub const CmdManager = struct {
    alloc: Allocator,
    gpi: vk.VkDevice,
    cmdPool: vk.VkCommandPool,
    cmds: []Command,

    queryPools: []vk.VkQueryPool,
    timestampPeriod: f32,
    maxQueries: u32 = 128,
    queryCounters: []u32,
    querys: CreateMapArray(Query, 128, u8, 128, 0) = .{},

    pub fn init(alloc: Allocator, context: *const Context, maxInFlight: u32) !CmdManager {
        const gpi = context.gpi;
        const cmdPool = try createCmdPool(gpi, context.families.graphics);

        const cmds = try alloc.alloc(Command, maxInFlight);
        for (0..maxInFlight) |i| cmds[i] = try Command.init(try createCmd(gpi, cmdPool, vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY));

        var props: vk.VkPhysicalDeviceProperties = undefined;
        vk.vkGetPhysicalDeviceProperties(context.gpu, &props);
        const timestampPeriod = props.limits.timestampPeriod;

        const poolInfo = vk.VkQueryPoolCreateInfo{
            .sType = vk.VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO,
            .queryType = vk.VK_QUERY_TYPE_TIMESTAMP,
            .queryCount = 128,
        };

        const queryPools = try alloc.alloc(vk.VkQueryPool, maxInFlight);
        for (0..maxInFlight) |i| {
            try vh.check(vk.vkCreateQueryPool(context.gpi, &poolInfo, null, &queryPools[i]), "Could not init QueryPool");
        }

        const queryCounters = try alloc.alloc(u32, maxInFlight);
        @memset(queryCounters, 0);

        return .{
            .alloc = alloc,
            .gpi = gpi,
            .cmdPool = cmdPool,
            .cmds = cmds,
            .queryPools = queryPools,
            .timestampPeriod = timestampPeriod,
            .queryCounters = queryCounters,
        };
    }

    pub fn deinit(self: *CmdManager) void {
        self.alloc.free(self.cmds);
        vk.vkDestroyCommandPool(self.gpi, self.cmdPool, null);

        for (self.queryPools) |pool| vk.vkDestroyQueryPool(self.gpi, pool, null);
        self.alloc.free(self.queryPools);
        self.alloc.free(self.queryCounters);
    }

    pub fn getCmd(self: *CmdManager, flightId: u8) !Command {
        const cmd = self.cmds[flightId];
        try vh.check(vk.vkResetCommandBuffer(cmd.handle, 0), "could not reset command buffer"); // Might be optional
        return cmd;
    }

    pub fn resetQueryPool(self: *CmdManager, cmd: *const Command, flightId: u8) void {
        vk.vkCmdResetQueryPool(cmd.handle, self.queryPools[flightId], 0, self.maxQueries);
        self.queryCounters[flightId] = 0;
    }

    pub fn startQuery(self: *CmdManager, cmd: *const Command, flightId: u8, pipeStage: vh.PipeStage, queryId: u8, name: []const u8) void {
        if (self.querys.isKeyUsed(queryId) == true) {
            std.debug.print("Warning: Query ID {} in use by {s}!", .{ queryId, self.querys.getPtr(queryId).name });
            return;
        }

        const idx = self.queryCounters[flightId];
        if (idx >= self.maxQueries) return; // Safety check

        cmd.writeTimestamp(self.queryPools[flightId], @intFromEnum(pipeStage), idx);
        self.querys.set(queryId, .{ .name = name, .startQueryIndex = idx });
        self.queryCounters[flightId] += 1;
    }

    pub fn endQuery(self: *CmdManager, cmd: *const Command, flightId: u8, pipeStage: vh.PipeStage, queryId: u8) void {
        if (self.querys.isKeyUsed(queryId) == false) {
            std.debug.print("Error: QueryId {} not registered", .{queryId});
            return;
        }

        const idx = self.queryCounters[flightId];
        if (idx >= self.maxQueries) return; // Safety check

        cmd.writeTimestamp(self.queryPools[flightId], @intFromEnum(pipeStage), idx);
        const query = self.querys.getPtr(queryId);
        query.endQueryIndex = idx;
        self.queryCounters[flightId] += 1;
    }

    pub fn resetQuerys(self: *CmdManager) void {
        self.querys.clear();
    }

    pub fn getQueryResults(self: *CmdManager, flightId: u8) !void {
        const count = self.queryCounters[flightId];
        if (count == 0 or count > self.maxQueries) return;

        var results: [128]u64 = undefined;
        const flags = vk.VK_QUERY_RESULT_64_BIT | vk.VK_QUERY_RESULT_WAIT_BIT;
        try vh.check(vk.vkGetQueryPoolResults(self.gpi, self.queryPools[flightId], 0, count, @sizeOf(u64) * 128, &results, @sizeOf(u64), flags), "Failed getting Queries");

        for (self.querys.getElements()) |query| {
            const diff = results[query.endQueryIndex] - results[query.startQueryIndex];
            const gpuTimeMs = (@as(f64, @floatFromInt(diff)) * self.timestampPeriod) / 1_000_000.0;

            std.debug.print("GPU: {d:.3} ms {s} \n", .{ gpuTimeMs, query.name });
        }
        std.debug.print("\n", .{});
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
