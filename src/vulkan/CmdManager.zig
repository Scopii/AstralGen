const std = @import("std");
const vk = @import("../modules/vk.zig").c;
const vkFn = @import("../modules/vk.zig");
const Allocator = std.mem.Allocator;
const Context = @import("Context.zig").Context;
const GpuImage = @import("resources/ResourceManager.zig").Resource.GpuImage;
const ResourceManager = @import("resources/ResourceManager.zig").ResourceManager;
const SwapchainManager = @import("SwapchainManager.zig");
const ShaderObject = @import("ShaderObject.zig").ShaderObject;
const PushConstants = @import("resources/DescriptorManager.zig").PushConstants;
const rc = @import("../configs/renderConfig.zig");
const RenderType = rc.Pass.PassType;
const sc = @import("../configs/shaderConfig.zig");
const MAX_WINDOWS = rc.MAX_WINDOWS;
const RENDER_IMG_STRETCH = rc.RENDER_IMG_STRETCH;
const CreateMapArray = @import("../structures/MapArray.zig").CreateMapArray;
const check = @import("ErrorHelpers.zig").check;

pub const CmdManager = struct {
    alloc: Allocator,
    gpi: vk.VkDevice,
    pool: vk.VkCommandPool,
    cmds: []vk.VkCommandBuffer,
    pipeLayout: vk.VkPipelineLayout,
    descLayoutAddress: u64,
    blitBarriers: [MAX_WINDOWS + 1]vk.VkImageMemoryBarrier2 = undefined,

    pub fn init(alloc: Allocator, context: *const Context, maxInFlight: u32, resMan: *const ResourceManager) !CmdManager {
        const gpi = context.gpi;
        const pool = try createCmdPool(gpi, context.families.graphics);

        const cmds = try alloc.alloc(vk.VkCommandBuffer, maxInFlight);
        for (0..maxInFlight) |i| cmds[i] = try createCmd(gpi, pool, vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY);

        return .{
            .alloc = alloc,
            .gpi = gpi,
            .pool = pool,
            .cmds = cmds,
            .pipeLayout = resMan.descMan.pipeLayout,
            .descLayoutAddress = resMan.descMan.descBuffer.gpuAddress,
        };
    }

    pub fn deinit(self: *CmdManager) void {
        self.alloc.free(self.cmds);
        vk.vkDestroyCommandPool(self.gpi, self.pool, null);
    }

    pub fn beginRecording(self: *CmdManager, frameInFlight: u8) !vk.VkCommandBuffer {
        const cmd = self.cmds[frameInFlight];
        try check(vk.vkResetCommandBuffer(cmd, 0), "could not reset command buffer"); // Might be optional

        const beginInf = vk.VkCommandBufferBeginInfo{
            .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT, //vk.VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT
            .pInheritanceInfo = null,
        };
        try check(vk.vkBeginCommandBuffer(cmd, &beginInf), "could not Begin CmdBuffer");
        return self.cmds[frameInFlight];
    }

    pub fn endRecording(cmd: vk.VkCommandBuffer) !void {
        try check(vk.vkEndCommandBuffer(cmd), "Could not End Cmd Buffer");
    }

    pub fn getCmd(self: *const CmdManager, frameInFlight: u8) vk.VkCommandBuffer {
        return self.cmds[frameInFlight];
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
    try check(vk.vkAllocateCommandBuffers(gpi, &allocInf, &cmd), "Could not create Cmd Buffer");
    return cmd;
}

fn createCmdPool(gpi: vk.VkDevice, familyIndex: u32) !vk.VkCommandPool {
    const poolInf = vk.VkCommandPoolCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = vk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT | vk.VK_COMMAND_POOL_CREATE_TRANSIENT_BIT,
        .queueFamilyIndex = familyIndex,
    };
    var pool: vk.VkCommandPool = undefined;
    try check(vk.vkCreateCommandPool(gpi, &poolInf, null, &pool), "Could not create Cmd Pool");
    return pool;
}