const std = @import("std");
const c = @import("../../c.zig");
const check = @import("../error.zig").check;
const Allocator = std.mem.Allocator;

pub const DescriptorManager = struct {
    alloc: Allocator,
    pool: c.VkDescriptorPool,
    sets: []c.VkDescriptorSet,

    pub fn init(alloc: Allocator, gpi: c.VkDevice, layout: c.VkDescriptorSetLayout, imageCount: u32) !DescriptorManager {
        // Create descriptor pool
        const poolSize = c.VkDescriptorPoolSize{
            .type = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
            .descriptorCount = imageCount,
        };

        const poolInfo = c.VkDescriptorPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .poolSizeCount = 1,
            .pPoolSizes = &poolSize,
            .maxSets = imageCount,
        };

        var pool: c.VkDescriptorPool = undefined;
        try check(c.vkCreateDescriptorPool(gpi, &poolInfo, null, &pool), "Failed to create descriptor pool");

        // Allocate descriptor sets
        const layouts = try alloc.alloc(c.VkDescriptorSetLayout, imageCount);
        defer alloc.free(layouts);
        for (layouts) |*layoutPtr| {
            layoutPtr.* = layout;
        }

        const allocInfo = c.VkDescriptorSetAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .descriptorPool = pool,
            .descriptorSetCount = imageCount,
            .pSetLayouts = layouts.ptr,
        };

        const sets = try alloc.alloc(c.VkDescriptorSet, imageCount);
        try check(c.vkAllocateDescriptorSets(gpi, &allocInfo, sets.ptr), "Failed to allocate descriptor sets");

        return .{
            .alloc = alloc,
            .pool = pool,
            .sets = sets,
        };
    }

    pub fn updateAllDescriptorSets(self: *DescriptorManager, gpi: c.VkDevice, imageView: c.VkImageView) void {
        // Batch all descriptor updates for better performance
        const imageInfos = self.alloc.alloc(c.VkDescriptorImageInfo, self.sets.len) catch unreachable;
        defer self.alloc.free(imageInfos);

        const writeDescriptors = self.alloc.alloc(c.VkWriteDescriptorSet, self.sets.len) catch unreachable;
        defer self.alloc.free(writeDescriptors);

        for (self.sets, 0..) |set, i| {
            imageInfos[i] = c.VkDescriptorImageInfo{
                .sampler = null,
                .imageView = imageView,
                .imageLayout = c.VK_IMAGE_LAYOUT_GENERAL,
            };

            writeDescriptors[i] = c.VkWriteDescriptorSet{
                .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = set,
                .dstBinding = 0,
                .dstArrayElement = 0,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
                .descriptorCount = 1,
                .pImageInfo = &imageInfos[i],
            };
        }

        // Single batch update instead of multiple calls
        c.vkUpdateDescriptorSets(gpi, @intCast(writeDescriptors.len), writeDescriptors.ptr, 0, null);
    }
    pub fn deinit(self: *DescriptorManager, gpi: c.VkDevice) void {
        c.vkDestroyDescriptorPool(gpi, self.pool, null);
        self.alloc.free(self.sets);
    }
};
