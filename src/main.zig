const std = @import("std");
const skgui = @import("skgui");

// bindings to the different libraries
const sokol = skgui.sokol;
const imp = skgui.implot;
const ig = skgui.imgui;

const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const print = @import("std").debug.print;

const state = struct {
    var pass_action: sg.PassAction = .{};
};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    var desc: sokol.imgui.Desc = .{};
    sokol.imgui.simgui_setup(&desc);
    _ = imp.ImPlot_CreateContext();

    // var io: *c.ImGuiIO = @ptrCast(c.igGetIO());
    // io.ConfigFlags |= c.ImGuiConfigFlags_NavEnableKeyboard;
    // io.ConfigFlags |= c.ImGuiConfigFlags_DockingEnable;
    // io.FontGlobalScale = 1.0 / io.DisplayFramebufferScale.y;

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
    };
    print("Backend: {}\n", .{sg.queryBackend()});
}

export fn frame() void {
    var new_frame: sokol.imgui.FrameDesc = .{
        .width = sapp.width(),
        .height = sapp.height(),
        .delta_time = sapp.frameDuration(),
        .dpi_scale = sapp.dpiScale(),
    };
    sokol.imgui.simgui_new_frame(&new_frame);

    drawGui() catch |err| {
        std.debug.print(">>> ERROR: {any}\n", .{err});
    };

    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
    sokol.imgui.render();
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    imp.ImPlot_DestroyContext(null);
    sokol.imgui.shutdown();
    sg.shutdown();
}

export fn event(ev: [*c]const sapp.Event) void {
    // forward input events to sokol-imgui
    _ = sokol.imgui.handleEvent(ev.*);
}

fn drawGui() !void {
    ig.igShowDemoWindow(null);
    imp.ImPlot_ShowDemoWindow(null);
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .width = 800,
        .height = 600,
        .window_title = "Example Application",
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
    });
}
