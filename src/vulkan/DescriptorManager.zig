const std = @import("std");
const c = @import("../c.zig");
const check = @import("error.zig").check;
const Context = @import("Context.zig").Context;
const Allocator = std.mem.Allocator;

pub const DescriptorManager = struct {
    alloc: Allocator,
    gpi: c.VkDevice,
    pool: c.VkDescriptorPool,
    sets: []c.VkDescriptorSet,
    computeLayout: c.VkDescriptorSetLayout,

    pub fn init(alloc: Allocator, context: *const Context, maxInFlight: u32) !DescriptorManager {
        const gpi = context.gpi;

        const poolSize = c.VkDescriptorPoolSize{
            .type = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
            .descriptorCount = maxInFlight,
        };

        const poolInfo = c.VkDescriptorPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .poolSizeCount = 1,
            .pPoolSizes = &poolSize,
            .maxSets = maxInFlight,
        };

        var pool: c.VkDescriptorPool = undefined;
        try check(c.vkCreateDescriptorPool(gpi, &poolInfo, null, &pool), "Failed to create descriptor pool");

        const computeLayout = try createComputeDescriptorSetLayout(gpi);
        errdefer c.vkDestroyDescriptorSetLayout(gpi, computeLayout, null);

        // Allocate descriptor sets
        const layouts = try alloc.alloc(c.VkDescriptorSetLayout, maxInFlight);
        defer alloc.free(layouts);
        for (layouts) |*layoutPtr| {
            layoutPtr.* = computeLayout;
        }

        const allocInfo = c.VkDescriptorSetAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .descriptorPool = pool,
            .descriptorSetCount = maxInFlight,
            .pSetLayouts = layouts.ptr,
        };

        const sets = try alloc.alloc(c.VkDescriptorSet, maxInFlight);
        try check(c.vkAllocateDescriptorSets(gpi, &allocInfo, sets.ptr), "Failed to allocate descriptor sets");

        return .{
            .alloc = alloc,
            .gpi = gpi,
            .pool = pool,
            .sets = sets,
            .computeLayout = computeLayout,
        };
    }

    fn createComputeDescriptorSetLayout(gpi: c.VkDevice) !c.VkDescriptorSetLayout {
        const binding = c.VkDescriptorSetLayoutBinding{
            .binding = 0,
            .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
            .descriptorCount = 1,
            .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT,
            .pImmutableSamplers = null,
        };

        const layoutInf = c.VkDescriptorSetLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = 1,
            .pBindings = &binding,
        };

        var descriptorSetLayout: c.VkDescriptorSetLayout = undefined;
        try check(c.vkCreateDescriptorSetLayout(gpi, &layoutInf, null, &descriptorSetLayout), "Failed to create descriptor set layout");
        return descriptorSetLayout;
    }

    pub fn updateAllDescriptorSets(self: *DescriptorManager, imageView: c.VkImageView) void {
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
        c.vkUpdateDescriptorSets(self.gpi, @intCast(writeDescriptors.len), writeDescriptors.ptr, 0, null);
    }

    pub fn deinit(self: *DescriptorManager) void {
        c.vkDestroyDescriptorSetLayout(self.gpi, self.computeLayout, null);
        c.vkDestroyDescriptorPool(self.gpi, self.pool, null);
        self.alloc.free(self.sets);
    }
};
