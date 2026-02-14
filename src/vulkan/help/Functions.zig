const rc = @import("../../configs/renderConfig.zig");
const vk = @import("../../modules/vk.zig").c;
const vkFn = @import("../../modules/vk.zig");
const vhE = @import("Enums.zig");
const std = @import("std");

pub fn getMemUsage(memUse: vhE.MemUsage) vk.VmaMemoryUsage {
    return switch (memUse) {
        .Gpu => vk.VMA_MEMORY_USAGE_GPU_ONLY,
        .CpuWrite => vk.VMA_MEMORY_USAGE_CPU_TO_GPU,
        .CpuRead => vk.VMA_MEMORY_USAGE_GPU_TO_CPU,
    };
}

pub fn getBufferUsageFlags(bufTyp: vhE.BufferType) vk.VkBufferUsageFlags {
    var bufUsageFlags: vk.VkBufferUsageFlags = switch (bufTyp) {
        .Storage => vk.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        .Uniform => vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
        .Index => vk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
        .Vertex => vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        .Staging => vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        .Indirect => vk.VK_BUFFER_USAGE_INDIRECT_BUFFER_BIT | vk.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
    };
    if (bufTyp != .Staging) bufUsageFlags |= vk.VK_BUFFER_USAGE_TRANSFER_DST_BIT | vk.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT;
    return bufUsageFlags;
}

pub fn getBufferAllocationFlags(memUse: vhE.MemUsage, bufTyp: vhE.BufferType) vk.VmaAllocationCreateFlags {
    var allocFlags: vk.VmaAllocationCreateFlags = switch (memUse) {
        .Gpu => 0,
        .CpuWrite, .CpuRead => vk.VMA_ALLOCATION_CREATE_MAPPED_BIT,
    };
    if (bufTyp == .Staging) allocFlags |= vk.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT;
    return allocFlags;
}

pub fn getImageFormat(texTyp: vhE.TextureType) vk.VkFormat {
    return switch (texTyp) {
        .Color => rc.TEX_COLOR_FORMAT,
        .Depth => rc.TEX_DEPTH_FORMAT,
        .Stencil => vk.VK_FORMAT_S8_UINT,
    };
}

pub fn getImageAspectFlags(texTyp: vhE.TextureType) vk.VkImageAspectFlags {
    return switch (texTyp) {
        .Color => vk.VK_IMAGE_ASPECT_COLOR_BIT,
        .Depth => vk.VK_IMAGE_ASPECT_DEPTH_BIT,
        .Stencil => vk.VK_IMAGE_ASPECT_STENCIL_BIT,
    };
}

pub fn getImageUse(texTyp: vhE.TextureType) vk.VkImageUsageFlags {
    var texUse: vk.VkImageUsageFlags = vk.VK_IMAGE_USAGE_TRANSFER_SRC_BIT | vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT;
    switch (texTyp) {
        .Color => texUse |= vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | vk.VK_IMAGE_USAGE_STORAGE_BIT,
        .Depth, .Stencil => texUse |= vk.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
    }
    return texUse;
}

pub fn getShaderBit(stageEnum: vhE.ShaderStage) vk.VkShaderStageFlagBits {
    return switch (stageEnum) {
        .comp => vk.VK_SHADER_STAGE_COMPUTE_BIT,
        .vert => vk.VK_SHADER_STAGE_VERTEX_BIT,
        .tessControl => vk.VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT,
        .tessEval => vk.VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT,
        .geometry => vk.VK_SHADER_STAGE_GEOMETRY_BIT,
        .task => vk.VK_SHADER_STAGE_TASK_BIT_EXT,
        .meshWithTask => vk.VK_SHADER_STAGE_MESH_BIT_EXT,
        .meshNoTask => vk.VK_SHADER_STAGE_MESH_BIT_EXT,
        .frag => vk.VK_SHADER_STAGE_FRAGMENT_BIT,
    };
}

pub fn check(result: vk.VkResult, comptime msg: []const u8) !void {
    if (result == vk.VK_SUCCESS) return;
    try errorHandle(result, msg);
}

fn errorHandle(result: vk.VkResult, comptime msg: []const u8) !void {
    switch (result) {
        vk.VK_TIMEOUT => std.log.err("{s} - Timeout", .{msg}),
        vk.VK_ERROR_OUT_OF_HOST_MEMORY => std.log.err("{s} - Out of Memory", .{msg}),
        vk.VK_ERROR_OUT_OF_DEVICE_MEMORY => std.log.err("{s} - Out of GPU Memory", .{msg}),
        vk.VK_ERROR_INITIALIZATION_FAILED => std.log.err("{s} - Initialization failed", .{msg}),
        vk.VK_ERROR_DEVICE_LOST => std.log.err("{s} - GPU lost", .{msg}),
        vk.VK_ERROR_MEMORY_MAP_FAILED => std.log.err("{s} - Memory Map Failed", .{msg}),
        else => std.log.err("{s} - Reason: {}", .{ msg, result }),
    }
    return error.VulkanError;
}

pub fn Handle(comptime _: type) type {
    return packed struct {
        id: u32,
        // pub inline fn raw(self: @This()) u32 {
        //     return self.id;
        // }
    };
}

pub fn setObjectName(device: vk.VkDevice, handle: anytype, objectType: vk.VkObjectType, name: []const u8) void {
    if (vkFn.vkSetDebugUtilsObjectNameEXT == null) return;

    var nameBuffer: [64]u8 = undefined;
    const len = @min(name.len, 63);
    @memcpy(nameBuffer[0..len], name[0..len]);
    nameBuffer[len] = 0; // Null terminate

    const nameInfo = vk.VkDebugUtilsObjectNameInfoEXT{
        .sType = vk.VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
        .objectType = objectType,
        .objectHandle = @intFromPtr(handle), // Cast handle (pointer) to u64
        .pObjectName = &nameBuffer,
    };

    _ = vkFn.vkSetDebugUtilsObjectNameEXT.?(device, &nameInfo);
}
// USAGE:
// vh.setObjectName(self.gpi, buffer.handle, vk.VK_OBJECT_TYPE_BUFFER, buffer.name);

// Synchronization

pub fn createSemaphore(gpi: vk.VkDevice) !vk.VkSemaphore {
    const semaphoreInf = vk.VkSemaphoreCreateInfo{ .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
    var semaphore: vk.VkSemaphore = undefined;
    try check(vk.vkCreateSemaphore(gpi, &semaphoreInf, null, &semaphore), "Could not create Semaphore");
    return semaphore;
}

pub fn createFence(gpi: vk.VkDevice) !vk.VkFence {
    const fenceInf = vk.VkFenceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = vk.VK_FENCE_CREATE_SIGNALED_BIT,
    };
    var fence: vk.VkFence = undefined;
    try check(vk.vkCreateFence(gpi, &fenceInf, null, &fence), "Could not create Fence");
    return fence;
}

pub fn createTimeline(gpi: vk.VkDevice) !vk.VkSemaphore {
    var semaphoreTypeInf: vk.VkSemaphoreTypeCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO,
        .semaphoreType = vk.VK_SEMAPHORE_TYPE_TIMELINE,
        .initialValue = 0,
    };
    const semaphoreInf = vk.VkSemaphoreCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        .pNext = &semaphoreTypeInf,
    };
    var semaphore: vk.VkSemaphore = undefined;
    try check(vk.vkCreateSemaphore(gpi, &semaphoreInf, null, &semaphore), "Could not create Timeline Semaphore");
    return semaphore;
}

pub fn waitForTimeline(gpi: vk.VkDevice, semaphore: vk.VkSemaphore, val: u64, timeout: u64) !void {
    const waitInf = vk.VkSemaphoreWaitInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO,
        .semaphoreCount = 1,
        .pSemaphores = &semaphore,
        .pValues = &val,
    };
    try check(vk.vkWaitSemaphores(gpi, &waitInf, timeout), "Failed to wait for timeline semaphore");
}

pub fn getTimelineVal(gpi: vk.VkDevice, semaphore: vk.VkSemaphore) !u64 {
    var val: u64 = 0;
    try check(vk.vkGetSemaphoreCounterValue(gpi, semaphore, &val), "Failed to get timeline semaphore value");
    return val;
}

// Texture Related

pub fn getViewCreateInfo(image: vk.VkImage, viewType: vk.VkImageViewType, format: vk.VkFormat, subRange: vk.VkImageSubresourceRange) vk.VkImageViewCreateInfo {
    return vk.VkImageViewCreateInfo{ .sType = vk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO, .pNext = null, .flags = 0, .image = image, .viewType = viewType, .format = format, .components = .{
        .r = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
        .g = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
        .b = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
        .a = vk.VK_COMPONENT_SWIZZLE_IDENTITY,
    }, .subresourceRange = subRange };
}

pub fn createSubresourceRange(mask: vk.VkImageAspectFlags, mipLevel: u32, levelCount: u32, arrayLayer: u32, layerCount: u32) vk.VkImageSubresourceRange {
    return vk.VkImageSubresourceRange{ .aspectMask = mask, .baseMipLevel = mipLevel, .levelCount = levelCount, .baseArrayLayer = arrayLayer, .layerCount = layerCount };
}
