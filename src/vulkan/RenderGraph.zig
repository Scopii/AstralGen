const std = @import("std");
const vk = @import("../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const rc = @import("../configs/renderConfig.zig");
const ResourceManager = @import("resources/ResourceManager.zig").ResourceManager;
const CreateMapArray = @import("../structures/MapArray.zig").CreateMapArray;
const ShaderObject = @import("ShaderObject.zig").ShaderObject;
const PushConstants = @import("resources/DescriptorManager.zig").PushConstants;
const vkFn = @import("../modules/vk.zig");
const sc = @import("../configs/shaderConfig.zig");
const GpuImage = @import("resources/ResourceManager.zig").Resource.GpuImage;
const SwapchainManager = @import("SwapchainManager.zig");

pub const ImageLayout = enum(vk.VkImageLayout) {
    Undefined = vk.VK_IMAGE_LAYOUT_UNDEFINED,
    General = vk.VK_IMAGE_LAYOUT_GENERAL,

    ColorAtt = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,

    DepthStencilAtt = vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    DepthStencilAttRead = vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_READ_ONLY_OPTIMAL,

    DepthAtt = vk.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
    DepthAttRead = vk.VK_IMAGE_LAYOUT_DEPTH_READ_ONLY_OPTIMAL,
    StencilAtt = vk.VK_IMAGE_LAYOUT_STENCIL_ATTACHMENT_OPTIMAL,

    StencilAttRead = vk.VK_IMAGE_LAYOUT_STENCIL_READ_ONLY_OPTIMAL,

    TransferSrc = vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
    TransferDst = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,

    PresentSrc = vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    //.. more exist
};

pub const PipeStage = enum(vk.VkPipelineStageFlagBits2) { //( SHOULD BE CORRECT ORDER)
    TopOfPipe = vk.VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
    Compute = vk.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
    VertShader = vk.VK_PIPELINE_STAGE_2_VERTEX_SHADER_BIT,
    TaskShader = vk.VK_PIPELINE_STAGE_2_TASK_SHADER_BIT_EXT,
    MeshShader = vk.VK_PIPELINE_STAGE_2_MESH_SHADER_BIT_EXT,
    FragShader = vk.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
    EarlyFragTest = vk.VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT,
    ColorAtt = vk.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
    LatFragTest = vk.VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT,
    AllGraphics = vk.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
    Transfer = vk.VK_PIPELINE_STAGE_2_TRANSFER_BIT,
    AllCmds = vk.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
    BotOfPipe = vk.VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT,
    //.. more exist
};

pub const PipeAccess = enum(vk.VkAccessFlagBits2) {
    None = 0,
    ShaderRead = vk.VK_ACCESS_2_SHADER_STORAGE_READ_BIT,
    ShaderWrite = vk.VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,
    ShaderReadWrite = vk.VK_ACCESS_2_SHADER_STORAGE_READ_BIT | vk.VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT,

    ColorAttWrite = vk.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
    ColorAttRead = vk.VK_ACCESS_2_COLOR_ATTACHMENT_READ_BIT,
    ColorAttReadWrite = vk.VK_ACCESS_2_COLOR_ATTACHMENT_READ_BIT | vk.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,

    DepthStencilRead = vk.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT,
    DepthStencilWrite = vk.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,

    TransferRead = vk.VK_ACCESS_2_TRANSFER_READ_BIT,
    TransferWrite = vk.VK_ACCESS_2_TRANSFER_WRITE_BIT,
    TransferReadWrite = vk.VK_ACCESS_2_TRANSFER_READ_BIT | vk.VK_ACCESS_2_TRANSFER_WRITE_BIT,

    MemoryRead = vk.VK_ACCESS_2_MEMORY_READ_BIT,
    MemoryWrite = vk.VK_ACCESS_2_MEMORY_WRITE_BIT,
    MemoryReadWrite = vk.VK_ACCESS_2_MEMORY_READ_BIT | vk.VK_ACCESS_2_MEMORY_WRITE_BIT,
    //.. more exist
};

pub const ResourceState = struct {
    stage: PipeStage = .TopOfPipe,
    access: PipeAccess = .None,
    layout: ImageLayout = .Undefined,
};

pub const RenderGraph = struct {
    alloc: Allocator,
    pipeLayout: vk.VkPipelineLayout,
    resourceStates: CreateMapArray(ResourceState, rc.GPU_RESOURCE_MAX, u32, rc.GPU_RESOURCE_MAX, 0) = .{},
    tempBarriers: std.array_list.Managed(vk.VkImageMemoryBarrier2),

    pub fn init(alloc: Allocator, resourceMan: *ResourceManager) RenderGraph {
        return .{
            .alloc = alloc,
            .pipeLayout = resourceMan.descMan.pipeLayout,
            .tempBarriers = std.array_list.Managed(vk.VkImageMemoryBarrier2).init(alloc),
        };
    }

    pub fn deinit(self: *RenderGraph) void {
        self.tempBarriers.deinit();
    }

    pub fn recordPassBarriers(self: *RenderGraph, cmd: vk.VkCommandBuffer, pass: rc.Pass, resMan: *ResourceManager) !void {
        for (pass.resUsages) |resUsage| {
            // CHECK IF RESOURCE IS ALREADY SET
            if (!self.resourceStates.isKeyUsed(resUsage.id)) {
                self.resourceStates.set(resUsage.id, .{});
            }

            const state = self.resourceStates.get(resUsage.id);
            const neededState = ResourceState{ .stage = resUsage.stage, .access = resUsage.access, .layout = resUsage.layout };

            if (state.stage != neededState.stage or state.access != neededState.access or state.layout != neededState.layout) {
                const resource = try resMan.getResourcePtr(resUsage.id);

                switch (resource.resourceType) {
                    .gpuImg => |*gpuImg| {
                        const barrier = createImageBarrier(state, neededState, gpuImg.img, gpuImg.imgInf.imgType);
                        try self.tempBarriers.append(barrier);
                        self.updateResourceState(resUsage);
                    },
                    .gpuBuf => std.debug.print("ERROR: Buffer Render Graph Build not implemented yet\n", .{}),
                }
            }
        }
        self.bakeBarriers(cmd);
    }

    pub fn recordPass(self: *RenderGraph, cmd: vk.VkCommandBuffer, pass: rc.Pass, pcs: PushConstants, validShaders: []const ShaderObject, resMan: *ResourceManager) !void {
        switch (pass.passType) {
            .computePass => try self.recordCompute(cmd, pass, pcs, validShaders, resMan),
            .graphicsPass, .meshPass, .taskMeshPass => try self.recordGraphics(cmd, pass, pcs, validShaders, resMan),
            else => std.debug.print("Renderer: {s} has no Command Recording yet\n", .{@tagName(pass.passType)}),
        }
    }

    pub fn recordCompute(self: *RenderGraph, cmd: vk.VkCommandBuffer, pass: rc.Pass, pcs: PushConstants, validShaders: []const ShaderObject, resMan: *ResourceManager) !void {
        if (pass.attachments.len > 1) std.debug.print("WARNING: Compute Pass only supports Attachment Standard\n", .{});

        const attachmentIndex = for (pass.attachments) |attachment| {
            if (attachment.renderType == .Color) break attachment.id;
        } else null;

        if (attachmentIndex == null) {
            std.debug.print("Compute needs Attachment! \n", .{});
            return error.RecordCompute;
        }
        const resource = try resMan.getResourcePtr(attachmentIndex.?);

        switch (resource.resourceType) {
            .gpuImg => |gpuImg| {
                vk.vkCmdPushConstants(cmd, self.pipeLayout, vk.VK_SHADER_STAGE_ALL, 0, @sizeOf(PushConstants), &pcs);
                bindShaderStages(cmd, validShaders);
                vk.vkCmdDispatch(cmd, (gpuImg.imgInf.extent.width + 7) / 8, (gpuImg.imgInf.extent.height + 7) / 8, 1);
            },
            else => {
                std.debug.print("ERROR: Compute Pass needs 1 Render Image, has none\n", .{});
                return error.ComputePassNotPossible;
            },
        }
    }

    pub fn recordGraphics(self: *RenderGraph, cmd: vk.VkCommandBuffer, pass: rc.Pass, pcs: PushConstants, validShaders: []const ShaderObject, resMan: *ResourceManager) !void {
        vk.vkCmdPushConstants(cmd, self.pipeLayout, vk.VK_SHADER_STAGE_ALL, 0, @sizeOf(PushConstants), &pcs);
        bindShaderStages(cmd, validShaders);

        if (pass.attachments.len > 3) return error.TooManyAttachments;

        var colorAttImg: ?*GpuImage = null;
        var depthAttImg: ?*GpuImage = null;
        var stencilAttImg: ?*GpuImage = null;

        for (pass.attachments) |attachment| {
            switch (attachment.renderType) {
                .Color => colorAttImg = try resMan.getImagePtr(attachment.id),
                .Depth => depthAttImg = try resMan.getImagePtr(attachment.id),
                .Stencil => stencilAttImg = try resMan.getImagePtr(attachment.id),
            }
        }

        const colorAtt = if (colorAttImg) |img| createAttachment(.Color, img.view, pass.clearColor) else null;
        const depthAtt = if (depthAttImg) |img| createAttachment(.Depth, img.view, pass.clearDepth) else null;
        const stencilAtt = if (stencilAttImg) |img| createAttachment(.Stencil, img.view, pass.clearStencil) else null;

        try renderWithState(cmd, colorAttImg.?, colorAtt, depthAtt, stencilAtt, pass);
    }

    pub fn recordSwapchainBlits(self: *RenderGraph, cmd: vk.VkCommandBuffer, targets: []const u32, swapchainMap: *SwapchainManager.SwapchainMap, resMan: *ResourceManager) !void {
        // Render Image and Swapchain Preperations
        for (targets) |swapchainIndex| {
            const swapchain = swapchainMap.getPtrAtIndex(swapchainIndex);
            const imgId = swapchain.passImgId;
            const srcImgPtr = try resMan.getImagePtr(imgId);

            const imgState = self.resourceStates.get(imgId);
            const neededImgState = ResourceState{ .stage = .Transfer, .access = .TransferRead, .layout = .TransferSrc };

            if (imgState.stage != neededImgState.stage or imgState.access != neededImgState.access or imgState.layout != neededImgState.layout) {
                // Transition Source Image (Color/General -> Transfer Src)
                const imgBarrier = createImageBarrier(imgState, neededImgState, srcImgPtr.img, srcImgPtr.imgInf.imgType);
                try self.tempBarriers.append(imgBarrier);
                self.resourceStates.set(imgId, neededImgState);
            }
            // Transition Destination Swapchain (Undefined -> Transfer Dst)
            const swapchainState = ResourceState{ .stage = .TopOfPipe, .access = .None, .layout = .Undefined };
            const neededState = ResourceState{ .stage = .Transfer, .access = .TransferWrite, .layout = .TransferDst };
            const swapchainBarrier = createImageBarrier(swapchainState, neededState, swapchain.images[swapchain.curIndex], .Color); // SHOULD THIS BE COLOR ?!
            try self.tempBarriers.append(swapchainBarrier); // Managed by Swapchain, needs no State Update
        }
        self.bakeBarriers(cmd);

        // Blits
        for (targets) |swapchainIndex| {
            const swapchain = swapchainMap.getPtrAtIndex(swapchainIndex);
            const renderImgPtr = try resMan.getImagePtr(swapchain.passImgId);
            const blitOffsets = calculateBlitOffsets(renderImgPtr.imgInf.extent, .{ .height = swapchain.extent.height, .width = swapchain.extent.width, .depth = 1 }, rc.RENDER_IMG_STRETCH);
            copyImageToImage(cmd, renderImgPtr.img, blitOffsets.srcOffsets, swapchain.images[swapchain.curIndex], blitOffsets.dstOffsets, rc.RENDER_IMG_STRETCH);
        }

        // Swapchain Presentation Barriers
        for (targets) |swapchainIndex| {
            // DOESNT HANDLE EDGECASE WHERE BLIT WASNT DONE BECAUSE NO WINDOW SHOWED THE RENDER
            const swapchain = swapchainMap.getPtrAtIndex(swapchainIndex);
            const swapchainState = ResourceState{ .stage = .TopOfPipe, .access = .None, .layout = .TransferDst }; // EDGE CASE: Probably Transfer?!
            const neededState = ResourceState{ .stage = .BotOfPipe, .access = .None, .layout = .PresentSrc };
            const barrier = createImageBarrier(swapchainState, neededState, swapchain.images[swapchain.curIndex], .Color);
            try self.tempBarriers.append(barrier);
        }
        self.bakeBarriers(cmd);
    }

    fn bakeBarriers(self: *RenderGraph, cmd: vk.VkCommandBuffer) void {
        createPipelineBarriers2(cmd, self.tempBarriers.items);
        self.tempBarriers.clearRetainingCapacity();
    }

    fn updateResourceState(self: *RenderGraph, resUsage: rc.Pass.ResourceUsage) void {
        self.resourceStates.set(resUsage.id, .{ .stage = resUsage.stage, .access = resUsage.access, .layout = resUsage.layout });
    }

    pub fn resetResourceState(self: *RenderGraph, id: u32) void {
        self.resourceStates.set(id, .{});
    }
};

fn createImageBarrier(curState: ResourceState, newState: ResourceState, img: vk.VkImage, imgType: rc.ImgType) vk.VkImageMemoryBarrier2 {
    const aspectMask: vk.VkImageAspectFlagBits = switch (imgType) {
        .Color => vk.VK_IMAGE_ASPECT_COLOR_BIT,
        .Depth => vk.VK_IMAGE_ASPECT_DEPTH_BIT,
        .Stencil => vk.VK_IMAGE_ASPECT_STENCIL_BIT,
    };

    return vk.VkImageMemoryBarrier2{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = @intFromEnum(curState.stage),
        .srcAccessMask = @intFromEnum(curState.access),
        .dstStageMask = @intFromEnum(newState.stage),
        .dstAccessMask = @intFromEnum(newState.access),
        .oldLayout = @intFromEnum(curState.layout),
        .newLayout = @intFromEnum(newState.layout),
        .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .image = img,
        .subresourceRange = createSubresourceRange(aspectMask, 0, 1, 0, 1),
    };
}

fn createBufferBarrier(curState: ResourceState, newState: ResourceState, buffer: vk.VkBuffer) vk.VkBufferMemoryBarrier2 {
    return vk.VkBufferMemoryBarrier2{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = @intFromEnum(curState.stage),
        .srcAccessMask = @intFromEnum(curState.access),
        .dstStageMask = @intFromEnum(newState.stage),
        .dstAccessMask = @intFromEnum(newState.access),
        .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
        .buffer = buffer,
        .offset = 0,
        .size = vk.VK_WHOLE_SIZE, // whole Buffer
    };
}

fn createPipelineBarriers2(cmd: vk.VkCommandBuffer, barriers: []const vk.VkImageMemoryBarrier2) void {
    const depInf = vk.VkDependencyInfo{
        .sType = vk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = @intCast(barriers.len),
        .pImageMemoryBarriers = barriers.ptr,
    };
    vk.vkCmdPipelineBarrier2(cmd, &depInf);
}

fn createSubresourceRange(mask: u32, mipLevel: u32, levelCount: u32, arrayLayer: u32, layerCount: u32) vk.VkImageSubresourceRange {
    return vk.VkImageSubresourceRange{ .aspectMask = mask, .baseMipLevel = mipLevel, .levelCount = levelCount, .baseArrayLayer = arrayLayer, .layerCount = layerCount };
}

fn createSubresourceLayers(mask: u32, mipLevel: u32, arrayLayer: u32, layerCount: u32) vk.VkImageSubresourceLayers {
    return vk.VkImageSubresourceLayers{ .aspectMask = mask, .mipLevel = mipLevel, .baseArrayLayer = arrayLayer, .layerCount = layerCount };
}

fn bindShaderStages(cmd: vk.VkCommandBuffer, shaderObjects: []const ShaderObject) void {
    const allStages = [_]vk.VkShaderStageFlagBits{
        vk.VK_SHADER_STAGE_VERTEX_BIT,
        vk.VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT,
        vk.VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT,
        vk.VK_SHADER_STAGE_GEOMETRY_BIT,
        vk.VK_SHADER_STAGE_FRAGMENT_BIT,
        vk.VK_SHADER_STAGE_COMPUTE_BIT,
        vk.VK_SHADER_STAGE_TASK_BIT_EXT,
        vk.VK_SHADER_STAGE_MESH_BIT_EXT,
    };
    var handles: [8]vk.VkShaderEXT = .{null} ** 8;

    for (shaderObjects) |shader| {
        const activeStageBit = sc.getShaderBit(shader.stage);

        for (0..8) |i| {
            if (allStages[i] == activeStageBit) {
                handles[i] = shader.handle;
                break;
            }
        }
    }
    vkFn.vkCmdBindShadersEXT.?(cmd, 8, &allStages, &handles);
}

fn createAttachment(renderType: enum { Color, Depth, Stencil }, imgView: vk.VkImageView, clear: bool) vk.VkRenderingAttachmentInfo {
    const imageLayout: vk.VkImageLayout = switch (renderType) {
        .Color => vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .Depth, .Stencil => vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    };

    const clearValue: vk.VkClearValue = switch (renderType) {
        .Color => .{ .color = .{ .float32 = .{ 0.0, 0.0, 0.1, 1.0 } } },
        .Depth, .Stencil => .{ .depthStencil = .{ .depth = 1.0, .stencil = 0 } },
    };

    return vk.VkRenderingAttachmentInfo{
        .sType = vk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = imgView,
        .imageLayout = imageLayout,
        .loadOp = if (clear) vk.VK_ATTACHMENT_LOAD_OP_CLEAR else vk.VK_ATTACHMENT_LOAD_OP_LOAD,
        .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = clearValue, // ✓ Now correct per type
    };
}

fn renderWithState(
    cmd: vk.VkCommandBuffer,
    mainImg: *GpuImage,
    colorAtt: ?vk.VkRenderingAttachmentInfo,
    depthAtt: ?vk.VkRenderingAttachmentInfo,
    stencilAtt: ?vk.VkRenderingAttachmentInfo,
    pass: rc.Pass,
) !void {
    var colorAttCopy = colorAtt;
    var depthAttCopy = depthAtt;
    var stencilAttCopy = stencilAtt;

    const scissor = vk.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = .{ .width = mainImg.imgInf.extent.width, .height = mainImg.imgInf.extent.height },
    };

    const renderInf = vk.VkRenderingInfo{
        .sType = vk.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .flags = 0,
        .renderArea = scissor,
        .layerCount = 1,
        .colorAttachmentCount = if (colorAtt != null) 1 else 0,
        .pColorAttachments = if (colorAttCopy != null) &colorAttCopy.? else null,
        .pDepthAttachment = if (depthAttCopy != null) &depthAttCopy.? else null,
        .pStencilAttachment = if (stencilAttCopy != null) &stencilAttCopy.? else null,
    };
    vk.vkCmdBeginRendering(cmd, &renderInf);

    const viewport = vk.VkViewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(mainImg.imgInf.extent.width),
        .height = @floatFromInt(mainImg.imgInf.extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    vkFn.vkCmdSetViewportWithCount.?(cmd, 1, &viewport);
    vkFn.vkCmdSetScissorWithCount.?(cmd, 1, &scissor);

    vkFn.vkCmdSetRasterizerDiscardEnable.?(cmd, vk.VK_FALSE);
    vkFn.vkCmdSetDepthBiasEnable.?(cmd, vk.VK_FALSE);
    vkFn.vkCmdSetPolygonModeEXT.?(cmd, vk.VK_POLYGON_MODE_FILL);
    vkFn.vkCmdSetRasterizationSamplesEXT.?(cmd, vk.VK_SAMPLE_COUNT_1_BIT);

    const sampleMask: u32 = 0xFFFFFFFF;
    vkFn.vkCmdSetSampleMaskEXT.?(cmd, vk.VK_SAMPLE_COUNT_1_BIT, &sampleMask);

    vkFn.vkCmdSetDepthClampEnableEXT.?(cmd, vk.VK_FALSE);
    vkFn.vkCmdSetAlphaToOneEnableEXT.?(cmd, vk.VK_FALSE);
    vkFn.vkCmdSetAlphaToCoverageEnableEXT.?(cmd, vk.VK_FALSE);
    vkFn.vkCmdSetLogicOpEnableEXT.?(cmd, vk.VK_FALSE);
    vkFn.vkCmdSetCullMode.?(cmd, vk.VK_CULL_MODE_FRONT_BIT);
    vkFn.vkCmdSetFrontFace.?(cmd, vk.VK_FRONT_FACE_CLOCKWISE);
    vkFn.vkCmdSetDepthTestEnable.?(cmd, vk.VK_FALSE);
    vkFn.vkCmdSetDepthWriteEnable.?(cmd, vk.VK_FALSE);
    vkFn.vkCmdSetDepthBoundsTestEnable.?(cmd, vk.VK_FALSE);
    vkFn.vkCmdSetStencilTestEnable.?(cmd, vk.VK_FALSE);

    const colorBlendEnable = vk.VK_TRUE;
    const colorBlendAttachments = [_]vk.VkBool32{colorBlendEnable};
    vkFn.vkCmdSetColorBlendEnableEXT.?(cmd, 0, 1, &colorBlendAttachments);

    const blendEquation = vk.VkColorBlendEquationEXT{
        .srcColorBlendFactor = vk.VK_BLEND_FACTOR_SRC_ALPHA,
        .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = vk.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = vk.VK_BLEND_OP_ADD,
    };
    const equations = [_]vk.VkColorBlendEquationEXT{blendEquation};
    vkFn.vkCmdSetColorBlendEquationEXT.?(cmd, 0, 1, &equations);

    const colorWriteMask = vk.VK_COLOR_COMPONENT_R_BIT | vk.VK_COLOR_COMPONENT_G_BIT | vk.VK_COLOR_COMPONENT_B_BIT | vk.VK_COLOR_COMPONENT_A_BIT;
    const colorWriteMasks = [_]vk.VkColorComponentFlags{colorWriteMask};
    vkFn.vkCmdSetColorWriteMaskEXT.?(cmd, 0, 1, &colorWriteMasks);

    vkFn.vkCmdSetPrimitiveTopology.?(cmd, vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST);
    vkFn.vkCmdSetPrimitiveRestartEnable.?(cmd, vk.VK_FALSE);

    switch (pass.passType) {
        .graphicsPass => {
            vkFn.vkCmdSetVertexInputEXT.?(cmd, 0, null, 0, null); // Currently empty vertex input state
            vk.vkCmdDraw(cmd, 3, 1, 0, 0);
        },
        .meshPass, .taskMeshPass => vkFn.vkCmdDrawMeshTasksEXT.?(cmd, 1, 1, 1),
        else => return error.UnsupportedPipelineType,
    }
    vk.vkCmdEndRendering(cmd);
}

pub fn copyImageToImage(cmd: vk.VkCommandBuffer, srcImg: vk.VkImage, srcOffsets: [2]vk.VkOffset3D, dstImg: vk.VkImage, dstOffsets: [2]vk.VkOffset3D, stretch: bool) void {
    const blitRegion = vk.VkImageBlit2{
        .sType = vk.VK_STRUCTURE_TYPE_IMAGE_BLIT_2,
        .srcSubresource = createSubresourceLayers(vk.VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
        .srcOffsets = srcOffsets,
        .dstSubresource = createSubresourceLayers(vk.VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
        .dstOffsets = dstOffsets,
    };
    const blitInf = vk.VkBlitImageInfo2{
        .sType = vk.VK_STRUCTURE_TYPE_BLIT_IMAGE_INFO_2,
        .dstImage = dstImg,
        .dstImageLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .srcImage = srcImg,
        .srcImageLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        .filter = if (stretch) vk.VK_FILTER_LINEAR else vk.VK_FILTER_NEAREST, // Linear for stretch, Nearest for pixel-perfect
        .regionCount = 1,
        .pRegions = &blitRegion,
    };
    vk.vkCmdBlitImage2(cmd, &blitInf);
}

fn calculateBlitOffsets(srcImgExtent: vk.VkExtent3D, dstImgExtent: vk.VkExtent3D, stretch: bool) struct { srcOffsets: [2]vk.VkOffset3D, dstOffsets: [2]vk.VkOffset3D } {
    var srcOffsets: [2]vk.VkOffset3D = undefined;
    var dstOffsets: [2]vk.VkOffset3D = undefined;

    if (stretch == true) {
        // Stretch: Source is full image, Dest is full window
        srcOffsets[0] = .{ .x = 0, .y = 0, .z = 0 };
        srcOffsets[1] = .{ .x = @intCast(srcImgExtent.width), .y = @intCast(srcImgExtent.height), .z = 1 };
        dstOffsets[0] = .{ .x = 0, .y = 0, .z = 0 };
        dstOffsets[1] = .{ .x = @intCast(dstImgExtent.width), .y = @intCast(dstImgExtent.height), .z = 1 };
    } else {
        // No Stretch (Center / Crop)
        const srcW: i32 = @intCast(srcImgExtent.width);
        const srcH: i32 = @intCast(srcImgExtent.height);
        const winW: i32 = @intCast(dstImgExtent.width);
        const winH: i32 = @intCast(dstImgExtent.height);
        // Determine the size of the region to copy (smaller of the two dimensions)
        const blitW = @min(srcW, winW);
        const blitH = @min(srcH, winH);

        // Center the region on the SOURCE
        // If Source < Window, this is 0. If Source > Window, this crops the center.
        const srcX = @divFloor(srcW - blitW, 2);
        const srcY = @divFloor(srcH - blitH, 2);
        srcOffsets[0] = .{ .x = srcX, .y = srcY, .z = 0 };
        srcOffsets[1] = .{ .x = srcX + blitW, .y = srcY + blitH, .z = 1 };

        // Center the region on the DESTINATION
        // If Window > Source, this centers the image on screen. If Window < Source, this is 0.
        const dstX = @divFloor(winW - blitW, 2);
        const dstY = @divFloor(winH - blitH, 2);
        dstOffsets[0] = .{ .x = dstX, .y = dstY, .z = 0 };
        dstOffsets[1] = .{ .x = dstX + blitW, .y = dstY + blitH, .z = 1 };
    }
    return .{ .srcOffsets = srcOffsets, .dstOffsets = dstOffsets };
}
