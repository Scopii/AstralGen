const std = @import("std");
const c = @import("../../c.zig");
const check = @import("../error.zig").check;
const Allocator = std.mem.Allocator;


pub const DescriptorManager = struct {
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
            .pool = pool,
            .sets = sets,
        };
    }

    pub fn updateDescriptorSets(self: *DescriptorManager, gpi: c.VkDevice, imageViews: []c.VkImageView) void {
        // This assumes you want to update all sets with the first view if called this way,
        // or you can adapt it as needed. For this specific problem, the new function is better.
        if (imageViews.len > 0) {
            self.updateAllDescriptorSets(gpi, imageViews[0]);
        }
    }

    pub fn updateAllDescriptorSets(self: *DescriptorManager, gpi: c.VkDevice, imageView: c.VkImageView) void {
        for (self.sets) |set| {
            const imageInfo = c.VkDescriptorImageInfo{
                .sampler = null,
                .imageView = imageView,
                .imageLayout = c.VK_IMAGE_LAYOUT_GENERAL,
            };

            const writeDescriptor = c.VkWriteDescriptorSet{
                .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstSet = set,
                .dstBinding = 0,
                .dstArrayElement = 0,
                .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
                .descriptorCount = 1,
                .pImageInfo = &imageInfo,
            };

            c.vkUpdateDescriptorSets(gpi, 1, &writeDescriptor, 0, null);
        }
    }

    pub fn deinit(self: *DescriptorManager, alloc: Allocator, gpi: c.VkDevice) void {
        c.vkDestroyDescriptorPool(gpi, self.pool, null);
        alloc.free(self.sets);
    }
};
