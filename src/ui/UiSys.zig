const RendererQueue = @import("../render/RendererQueue.zig").RendererQueue;
const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;
const PassDef = @import("../render/types/pass/PassDef.zig");
const EngineData = @import("../EngineData.zig").EngineData;
const Window = @import("../window/Window.zig").Window;
const rc = @import("../.configs/renderConfig.zig");
const ig = @cImport(@cInclude("imgui_ctx.h"));
const UiData = @import("UiData.zig").UiData;
const zgui = @import("zgui");
const std = @import("std");

pub const UiSys = struct {
    pub fn init(ui: *UiData, memoryMan: *MemoryManager) !void {
        zgui.init(memoryMan.getAllocator());
        ui.baseContext = ig.igui_get_current_context();
        zgui.io.setBackendFlags(.{ .renderer_has_textures = true, .renderer_has_vtx_offset = true });

        // Force Atlas with Dummy Frame:
        zgui.io.setDisplaySize(1.0, 1.0);
        // zgui.io.setDeltaTime(1.0 / 60.0);
        zgui.newFrame();
        zgui.render();
        ui.fontAtlas = ig.igui_get_font_atlas();
        ui.initialized = true;
    }

    pub fn update(ui: *UiData, data: *const EngineData, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        ui.activeNodes = &.{};

        if (data.window.uiActive) {
            try processTextures(ui, rendererQueue, memoryMan);
            for (data.window.activeWindows.constSlice()) |*window| buildWindowUi(window, ui, data.time.deltaTime);
            try extractDrawData(ui, data, rendererQueue, memoryMan);
        }
    }

    fn processTextures(ui: *UiData, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        if (!ui.initialized) return;
        if (ui.contexts.getLength() == 0) return; // at least one window context to access shared atlas

        ig.igui_set_current_context(@ptrCast(ui.contexts.getFirst()));
        const texData = zgui.io.getFontsTexRef().tex_data orelse return;

        switch (texData.status) {
            .want_create, .want_updates => {
                // null check — atlas not baked yet (newFrame not called yet)
                if (texData.width == 0 or texData.height == 0) return;

                const width = texData.width;
                const height = texData.height;
                const pixelCount: usize = @intCast(width * height);
                const arena = memoryMan.getGlobalArena();

                const pixelBytes: []const u8 = blk: {
                    const bpp = texData.bytes_per_pixel;
                    if (bpp == 4) {
                        break :blk texData.pixels[0 .. pixelCount * 4];
                    } else if (bpp == 1) {
                        const expanded = try arena.alloc([4]u8, pixelCount);
                        for (0..pixelCount) |p| expanded[p] = .{ 255, 255, 255, texData.pixels[p] };
                        break :blk std.mem.sliceAsBytes(expanded);
                    } else return;
                };

                const PayloadPtr = @FieldType(RendererQueue.RendererEvent, "updateTexture");
                const updateTexPtr = try arena.create(std.meta.Child(PayloadPtr));
                updateTexPtr.* = .{
                    .texId = rc.imguiFontTex.id,
                    .data = pixelBytes,
                    .newExtent = .{ .width = @intCast(width), .height = @intCast(height), .depth = 1 },
                };
                rendererQueue.append(.{ .updateTexture = updateTexPtr });

                texData.tex_id = @enumFromInt(@as(u64, rc.imguiFontTex.id.val));
                texData.status = .ok;
            },
            .want_destroy => texData.status = .destroyed,
            .ok => {},
            else => {},
        }
    }

    fn buildWindowUi(window: *const Window, ui: *UiData, deltaTime: i128) void {
        if (!ui.initialized) return;

        if (!ui.contexts.isKeyUsed(window.id.val)) {
            // New Context
            const context = ig.igui_create_context(@ptrCast(ui.fontAtlas));
            ui.contexts.upsert(window.id.val, @ptrCast(context));
            ig.igui_set_current_context(@ptrCast(context));
            zgui.backend.initVulkan(window.handle);
            zgui.io.setBackendFlags(.{ .renderer_has_textures = true, .renderer_has_vtx_offset = true });
        } else {
            // Change Context
            ig.igui_set_current_context(@ptrCast(ui.contexts.getByKey(window.id.val)));
        }

        zgui.io.setDisplaySize(@floatFromInt(window.extent.width), @floatFromInt(window.extent.height));
        zgui.io.setDeltaTime(@as(f32, @floatFromInt(deltaTime)) * 1e-9);

        zgui.newFrame();

        // drawBorderUi(window, data);
        drawSimpleWindowUi(window);

        zgui.render();
    }

    fn drawSimpleWindowUi(window: *const Window) void {
        var buf: [32]u8 = undefined;
        const panelName = std.fmt.bufPrintZ(&buf, "Window (ID {d})", .{window.id.val}) catch "";
        if (zgui.begin(panelName, .{ .flags = .{ .no_background = true } })) {
            zgui.text("This UI controls OS window {d}", .{window.id.val});
            if (zgui.button("Settings2", .{})) {
                std.debug.print("Settings clicked on Window {}\n", .{window.id.val});
            }
        }
        zgui.end();
    }

    fn drawBorderUi(window: *const Window, data: *EngineData) void {
        const width = @as(f32, @floatFromInt(window.extent.width));
        const height = @as(f32, @floatFromInt(window.extent.height));

        const drawList = zgui.getForegroundDrawList();
        drawList.addRect(.{
            .pmin = .{ 0.0, 0.0 },
            .pmax = .{ width, height },
            .col = zgui.colorConvertFloat4ToU32(.{ 0.3, 0.3, 0.3, 1.0 }), // White
            .thickness = 1.0,
        });

        zgui.setNextWindowPos(.{ .x = 0.0, .y = 0.0 }); // Top left of window
        zgui.setNextWindowSize(.{ .w = width, .h = 0.0 }); // FUll Window Size

        var flags: zgui.WindowFlags = .{};
        flags.no_resize = true;
        flags.no_move = true;
        flags.no_background = true; // Opened Tab has no Background

        var buf: [32]u8 = undefined;
        const panelName = std.fmt.bufPrintZ(&buf, "Window (ID {d})", .{window.id.val}) catch "";

        // const style = zgui.getStyle();
        // const activeColor = style.colors[@intFromEnum(zgui.StyleCol.title_bg)];
        const activeColor = .{ 0.0, 0.0, 0.0, 0.5 };
        zgui.pushStyleColor4f(.{ .idx = zgui.StyleCol.title_bg_active, .c = activeColor });
        zgui.pushStyleColor4f(.{ .idx = zgui.StyleCol.title_bg_collapsed, .c = activeColor });
        zgui.pushStyleColor4f(.{ .idx = zgui.StyleCol.title_bg, .c = activeColor });

        zgui.pushStyleVar1f(.{ .idx = zgui.StyleVar.window_border_size, .v = 0.0 });

        const transparent = .{ 0.0, 0.0, 0.0, 0.0 };
        zgui.pushStyleColor4f(.{ .idx = zgui.StyleCol.nav_windowing_highlight, .c = transparent });

        // Collapsible ImGui Window
        if (zgui.begin(panelName, .{ .flags = flags })) {
            zgui.text("This UI controls the entire OS window.", .{});

            if (zgui.button("Settings", .{})) {
                std.debug.print("Settings clicked on Window {}\n", .{window.id.val});
            }
        }

        // border outline around viewport
        for (window.viewIds) |viewIdOpt| {
            if (viewIdOpt) |viewId| {
                if (data.viewport.viewports.isKeyUsed(viewId.val) == false) continue;

                const viewport = data.viewport.viewports.getByKey(viewId.val);
                const viewX = width * viewport.areaX;
                const viewY = height * viewport.areaY;
                const viewWidth = width * viewport.areaWidth;
                const viewHeight = height * viewport.areaHeight;

                drawList.addRect(.{
                    .pmin = .{ viewX, viewY },
                    .pmax = .{ viewX + viewWidth, viewY + viewHeight },
                    .col = zgui.colorConvertFloat4ToU32(.{ 0.3, 0.3, 0.3, 1.0 }),
                    .thickness = 1.0,
                });
            }
        }
        zgui.end();
        zgui.popStyleColor(.{ .count = 4 });
        zgui.popStyleVar(.{ .count = 1 });
    }

    fn extractDrawData(ui: *UiData, data: *const EngineData, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        const arena = memoryMan.getGlobalArena();
        var uiNodes = std.array_list.Managed(PassDef.UiNode).init(arena);

        var totalVtxBytes: u32 = 0;
        var totalIdxBytes: u32 = 0;

        for (data.window.activeWindows.constSlice()) |window| {
            if (!ui.contexts.isKeyUsed(window.id.val)) continue;
            ig.igui_set_current_context(@ptrCast(ui.contexts.getByKey(window.id.val)));

            const drawData = zgui.getDrawData();
            totalVtxBytes += @intCast(drawData.total_vtx_count * @sizeOf(zgui.DrawVert));
            totalIdxBytes += @intCast(drawData.total_idx_count * @sizeOf(zgui.DrawIdx));
        }
        if (totalVtxBytes == 0 or totalIdxBytes == 0) return;

        const vtxBuffer = try arena.alloc(u8, totalVtxBytes);
        const idxBuffer = try arena.alloc(u8, totalIdxBytes);
        var vtxCursor: u32 = 0;
        var idxCursor: u32 = 0;
        var globalVtxOffset: i32 = 0;
        var globalIdxOffset: u32 = 0;

        for (data.window.activeWindows.constSlice()) |window| {
            if (!ui.contexts.isKeyUsed(window.id.val)) continue;
            ig.igui_set_current_context(@ptrCast(ui.contexts.getByKey(window.id.val)));

            const drawData = zgui.getDrawData();
            if (drawData.total_vtx_count == 0) continue;

            var cmdListsArray = std.array_list.Managed(PassDef.UiNode.UiDraw).init(arena);

            for (drawData.cmd_lists.items[0..@intCast(drawData.cmd_lists_count)]) |cmdList| {
                const vtxData = cmdList.getVertexBuffer();
                const idxData = cmdList.getIndexBuffer();

                @memcpy(vtxBuffer[vtxCursor .. vtxCursor + vtxData.len * @sizeOf(zgui.DrawVert)], std.mem.sliceAsBytes(vtxData));
                @memcpy(idxBuffer[idxCursor .. idxCursor + idxData.len * @sizeOf(zgui.DrawIdx)], std.mem.sliceAsBytes(idxData));

                for (cmdList.getCmdBuffer()) |pcmd| {
                    if (pcmd.user_callback != null) continue;

                    var texIdVal: u32 = @intCast(@intFromEnum(pcmd.texture_ref.tex_id));
                    if (texIdVal == 0) texIdVal = rc.imguiFontTex.id.val;

                    try cmdListsArray.append(.{
                        .clipRect = pcmd.clip_rect,
                        .texId = .{ .val = texIdVal },
                        .vtxOffset = globalVtxOffset + @as(i32, @intCast(pcmd.vtx_offset)),
                        .idxOffset = globalIdxOffset + pcmd.idx_offset,
                        .elemCount = pcmd.elem_count,
                    });
                }

                vtxCursor += @intCast(vtxData.len * @sizeOf(zgui.DrawVert));
                idxCursor += @intCast(idxData.len * @sizeOf(zgui.DrawIdx));
                globalIdxOffset += @intCast(idxData.len);
                globalVtxOffset += @intCast(vtxData.len);
            }

            try uiNodes.append(.{
                .windowId = window.id,
                .displayPos = drawData.display_pos,
                .displaySize = drawData.display_size,
                .drawList = try cmdListsArray.toOwnedSlice(),
            });
        }
        ui.activeNodes = try uiNodes.toOwnedSlice();

        const PayloadVtx = @FieldType(RendererQueue.RendererEvent, "updateBuffer");
        const updateVtxPtr = try arena.create(std.meta.Child(PayloadVtx));
        updateVtxPtr.* = .{ .bufId = rc.imguiVertexSB.id, .data = vtxBuffer };
        rendererQueue.append(.{ .updateBuffer = updateVtxPtr });

        const PayloadIdx = @FieldType(RendererQueue.RendererEvent, "updateBuffer");
        const updateIdxPtr = try arena.create(std.meta.Child(PayloadIdx));
        updateIdxPtr.* = .{ .bufId = rc.imguiIndexSB.id, .data = idxBuffer };
        rendererQueue.append(.{ .updateBuffer = updateIdxPtr });
    }

    pub fn deinit(ui: *UiData) void {
        if (!ui.initialized) return;

        for (ui.contexts.getItems()) |ctx| {
            ig.igui_set_current_context(@ptrCast(ctx));
            zgui.backend.deinit();
            ig.igui_destroy_context(@ptrCast(ctx));
        }
        ui.contexts.clear();
        ig.igui_set_current_context(@ptrCast(ui.baseContext));
        zgui.deinit();
        ui.initialized = false;
    }
};
