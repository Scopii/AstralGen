const EngineData = @import("../EngineData.zig").EngineData;
const Window = @import("../window/Window.zig").Window;
const zgui = @import("zgui");
const std = @import("std");

pub const UiSys = struct {
    pub fn buildWindowUi(window: *const Window, data: *const EngineData) void {
        
        const winW = @as(f32, @floatFromInt(window.extent.width));
        const winH = @as(f32, @floatFromInt(window.extent.height));

        const drawList = zgui.getForegroundDrawList();
        drawList.addRect(.{
            .pmin = .{ 0.0, 0.0 },
            .pmax = .{ winW, winH },
            .col = zgui.colorConvertFloat4ToU32(.{ 0.3, 0.3, 0.3, 1.0 }), // White
            .thickness = 1.0,
        });

        zgui.setNextWindowPos(.{ .x = 0.0, .y = 0.0 }); // Top left of window
        zgui.setNextWindowSize(.{ .w = winW, .h = 0.0 }); // FUll Window Size

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
                const viewX = winW * viewport.areaX;
                const viewY = winH * viewport.areaY;
                const viewW = winW * viewport.areaWidth;
                const viewH = winH * viewport.areaHeight;

                drawList.addRect(.{
                    .pmin = .{ viewX, viewY },
                    .pmax = .{ viewX + viewW, viewY + viewH },
                    .col = zgui.colorConvertFloat4ToU32(.{ 0.3, 0.3, 0.3, 1.0 }),
                    .thickness = 1.0,
                });
            }
        }

        zgui.end();

        zgui.popStyleColor(.{ .count = 4 });
        zgui.popStyleVar(.{ .count = 1 });
    }
};
