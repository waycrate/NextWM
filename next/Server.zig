// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/Server.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const allocator = @import("utils/allocator.zig").allocator;
const build_options = @import("build_options");
const c = @import("utils/c.zig");
const log = std.log.scoped(.Server);
const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Config = @import("Config.zig");
const Control = @import("global/Control.zig");
const Cursor = @import("input/Cursor.zig");
const DecorationManager = @import("desktop/DecorationManager.zig");
const InputManager = @import("input/InputManager.zig");
const Keyboard = @import("input/Keyboard.zig");
const Output = @import("desktop/Output.zig");
const OutputLayout = @import("desktop/OutputLayout.zig");
const Seat = @import("input/Seat.zig");
const Window = @import("desktop/Window.zig");
const XdgToplevel = @import("desktop/XdgToplevel.zig");

const default_cursor_size = 24;

wl_server: *wl.Server,
wl_event_loop: *wl.EventLoop,
wlr_backend: *wlr.Backend,
wlr_headless_backend: *wlr.Backend,
wlr_renderer: *wlr.Renderer,
wlr_allocator: *wlr.Allocator,
wlr_scene: *wlr.Scene,
wlr_compositor: *wlr.Compositor,

wlr_foreign_toplevel_manager: *wlr.ForeignToplevelManagerV1,

config: Config,
control: Control,
decoration_manager: DecorationManager,
input_manager: InputManager,
output_layout: OutputLayout,
seat: Seat,

// Layers
layer_bg: *wlr.SceneTree,
layer_fullscreen: *wlr.SceneTree,
layer_bottom: *wlr.SceneTree,
layer_float: *wlr.SceneTree,
layer_nofocus: *wlr.SceneTree,
layer_overlay: *wlr.SceneTree,
layer_tile: *wlr.SceneTree,
layer_top: *wlr.SceneTree,

sigint_cb: *wl.EventSource,
sigterm_cb: *wl.EventSource,
sigkill_cb: *wl.EventSource,
sigabrt_cb: *wl.EventSource,
sigquit_cb: *wl.EventSource,

wlr_output_manager: *wlr.OutputManagerV1,
new_output: wl.Listener(*wlr.Output),

outputs: std.ArrayListUnmanaged(*Output),
keyboards: std.ArrayListUnmanaged(*Keyboard),
cursors: std.ArrayListUnmanaged(*Cursor),

wlr_xdg_shell: *wlr.XdgShell,
new_xdg_surface: wl.Listener(*wlr.XdgSurface),
mapped_windows: std.ArrayListUnmanaged(*Window),
pending_windows: std.ArrayListUnmanaged(*Window),

wlr_layer_shell: *wlr.LayerShellV1,
new_layer_surface: wl.Listener(*wlr.LayerSurfaceV1),

wlr_xwayland: if (build_options.xwayland) *wlr.Xwayland else void,
new_xwayland_surface: if (build_options.xwayland) wl.Listener(*wlr.XwaylandSurface) else void,

wlr_power_manager: *wlr.OutputPowerManagerV1,
set_mode: wl.Listener(*wlr.OutputPowerManagerV1.event.SetMode),

wlr_cursor: *wlr.Cursor,
wlr_xcursor_manager: *wlr.XcursorManager,

wlr_xdg_activation_v1: *wlr.XdgActivationV1,
request_activate: wl.Listener(*wlr.XdgActivationV1.event.RequestActivate),

pub fn init(self: *Self) !void {
    logInfo();

    self.wl_server = try wl.Server.create();
    errdefer self.wl_server.destroy();

    self.wl_event_loop = self.wl_server.getEventLoop();
    self.sigabrt_cb = try self.wl_event_loop.addSignal(*wl.Server, std.os.SIG.ABRT, terminateCb, self.wl_server);
    self.sigint_cb = try self.wl_event_loop.addSignal(*wl.Server, std.os.SIG.INT, terminateCb, self.wl_server);
    self.sigquit_cb = try self.wl_event_loop.addSignal(*wl.Server, std.os.SIG.QUIT, terminateCb, self.wl_server);
    self.sigterm_cb = try self.wl_event_loop.addSignal(*wl.Server, std.os.SIG.TERM, terminateCb, self.wl_server);

    // NOTE: This frees itself when the server is destroyed.
    self.wlr_backend = try wlr.Backend.autocreate(self.wl_server);

    // Created when no ouputs are available.
    // NOTE: This frees itself when server is destroyed.
    self.wlr_headless_backend = try wlr.Backend.createHeadless(self.wl_server);

    self.wlr_renderer = try wlr.Renderer.autocreate(self.wlr_backend);
    errdefer self.wlr_renderer.destroy();

    self.wlr_allocator = try wlr.Allocator.autocreate(self.wlr_backend, self.wlr_renderer);
    errdefer self.wlr_allocator.destroy();

    self.wlr_compositor = try wlr.Compositor.create(self.wl_server, self.wlr_renderer);
    _ = try wlr.Subcompositor.create(self.wl_server);

    //NOTE: This has to be initialized as one of the first wayland globals inorder to not crash on middle-button paste in gtk3...ugh.
    _ = try wlr.PrimarySelectionDeviceManagerV1.create(self.wl_server);

    self.wlr_foreign_toplevel_manager = try wlr.ForeignToplevelManagerV1.create(self.wl_server);

    self.wlr_scene = try wlr.Scene.create();

    try self.output_layout.init();

    self.wlr_output_manager = try wlr.OutputManagerV1.create(self.wl_server);
    _ = try wlr.XdgOutputManagerV1.create(self.wl_server, self.output_layout.wlr_output_layout);

    self.wlr_cursor = try wlr.Cursor.create();
    errdefer self.wlr_cursor.destroy();

    self.wlr_xdg_activation_v1 = try wlr.XdgActivationV1.create(self.wl_server);

    self.wlr_xcursor_manager = try wlr.XcursorManager.create(null, default_cursor_size);
    errdefer self.wlr_xcursor_manager.destroy();

    try self.wlr_xcursor_manager.load(1);

    self.wlr_xdg_shell = try wlr.XdgShell.create(self.wl_server, 5);
    self.wlr_layer_shell = try wlr.LayerShellV1.create(self.wl_server);
    self.wlr_power_manager = try wlr.OutputPowerManagerV1.create(self.wl_server);

    try self.seat.init();

    // Creating toplevel layers:
    self.layer_bg = try self.wlr_scene.tree.createSceneTree();
    self.layer_fullscreen = try self.wlr_scene.tree.createSceneTree(); // Used for direct_scanout.
    self.layer_bottom = try self.wlr_scene.tree.createSceneTree();
    self.layer_float = try self.wlr_scene.tree.createSceneTree();
    self.layer_nofocus = try self.wlr_scene.tree.createSceneTree();
    self.layer_overlay = try self.wlr_scene.tree.createSceneTree();
    self.layer_tile = try self.wlr_scene.tree.createSceneTree();
    self.layer_top = try self.wlr_scene.tree.createSceneTree();

    if (build_options.xwayland) {
        self.wlr_xwayland = try wlr.Xwayland.create(self.wl_server, self.wlr_compositor, build_options.xwayland_lazy);
        self.wlr_xwayland.setSeat(self.seat.wlr_seat);
    }

    try self.wlr_renderer.initServer(self.wl_server);
    try self.wlr_scene.attachOutputLayout(self.output_layout.wlr_output_layout);
    self.wlr_cursor.attachOutputLayout(self.output_layout.wlr_output_layout);

    // NOTE: These all free themselves when wlr_server is destroy.
    _ = try wlr.DataControlManagerV1.create(self.wl_server);
    _ = try wlr.DataDeviceManager.create(self.wl_server);
    _ = try wlr.ExportDmabufManagerV1.create(self.wl_server);
    _ = try wlr.GammaControlManagerV1.create(self.wl_server);
    _ = try wlr.ScreencopyManagerV1.create(self.wl_server);
    _ = try wlr.SinglePixelBufferManagerV1.create(self.wl_server);
    _ = try wlr.Viewporter.create(self.wl_server);

    try self.control.init();
    try self.decoration_manager.init();
    try self.input_manager.init();
    self.config = Config.init();

    self.new_output.setNotify(newOutput);
    self.wlr_backend.events.new_output.add(&self.new_output);

    self.new_xdg_surface.setNotify(newXdgSurface);
    self.wlr_xdg_shell.events.new_surface.add(&self.new_xdg_surface);

    self.set_mode.setNotify(setMode);
    self.wlr_power_manager.events.set_mode.add(&self.set_mode);

    self.new_layer_surface.setNotify(newLayerSurface);
    self.wlr_layer_shell.events.new_surface.add(&self.new_layer_surface);

    self.request_activate.setNotify(requestActivate);
    self.wlr_xdg_activation_v1.events.request_activate.add(&self.request_activate);

    if (build_options.xwayland) {
        self.new_xwayland_surface.setNotify(newXwaylandSurface);
        self.wlr_xwayland.events.new_surface.add(&self.new_xwayland_surface);
    }
}

pub fn start(self: *Self) !void {
    var buf: [11]u8 = undefined;
    const socket = try self.wl_server.addSocketAuto(&buf);

    if (c.setenv("WAYLAND_DISPLAY", socket.ptr, 1) < 0) return error.SetenvError;
    if (build_options.xwayland) if (c.setenv("DISPLAY", self.wlr_xwayland.display_name, 1) < 0) return error.SetenvError;

    try self.wlr_backend.start();
    log.info("Starting NextWM on {s}", .{socket});

    if (build_options.xwayland) {
        log.info("Xwayland initialized at {s}", .{self.wlr_xwayland.display_name});
    }
}

pub fn deinit(self: *Self) void {
    log.info("Cleaning up server resources", .{});
    self.sigabrt_cb.remove();
    self.sigint_cb.remove();
    self.sigquit_cb.remove();
    self.sigterm_cb.remove();

    if (build_options.xwayland) {
        self.wlr_xwayland.destroy();
    }
    self.wl_server.destroyClients();

    self.wlr_backend.destroy();
    self.wlr_renderer.destroy();
    self.wlr_allocator.destroy();

    for (self.mapped_windows.items) |item| {
        allocator.destroy(item);
    }
    self.mapped_windows.deinit(allocator);

    for (self.pending_windows.items) |item| {
        allocator.destroy(item);
    }
    self.pending_windows.deinit(allocator);

    for (self.outputs.items) |output| {
        output.deinit_wallpaper();
        allocator.destroy(output);
    }
    self.outputs.deinit(allocator);

    for (self.cursors.items) |item| {
        allocator.destroy(item);
    }
    self.cursors.deinit(allocator);

    for (self.keyboards.items) |item| {
        allocator.destroy(item);
    }
    self.keyboards.deinit(allocator);

    self.wlr_scene.tree.node.destroy();

    self.wlr_cursor.destroy();
    self.wlr_xcursor_manager.destroy();
    self.output_layout.deinit();

    self.seat.deinit();

    // Destroy the server.
    self.wl_server.destroy();
    self.config.deinit();
    log.info("Exiting NextWM...", .{});
}

// This is called to gracefully handle signals.
fn terminateCb(_: c_int, wl_server: *wl.Server) c_int {
    log.info("Terminating event loop.", .{});
    wl_server.terminate();
    return 0;
}

fn requestActivate(
    _: *wl.Listener(*wlr.XdgActivationV1.event.RequestActivate),
    event: *wlr.XdgActivationV1.event.RequestActivate,
) void {
    log.debug("Signal: wlr_xdg_activation_v1_request_activate", .{});
    // Handle xwayland and subsurfaces
    var window: ?*Window = null;
    if (event.surface.isXdgSurface()) {
        if (wlr.XdgSurface.fromWlrSurface(event.surface)) |xdg_surface| {
            if (xdg_surface.role == .toplevel) {
                window = @as(*Window, @ptrFromInt(xdg_surface.data));
            }
        }
    }

    //TODO: Focus on the window and warp the cursor to it's center?
    //if (window) |win| {
    //}
}

// Callback that gets triggered on existence of a new output.
fn newOutput(_: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
    log.debug("Signal: wlr_backend_new_output", .{});
    const output = allocator.create(Output) catch {
        std.log.err("Failed to allocate new output", .{});
        return;
    };
    errdefer allocator.destroy(output);

    // Instantiate the output struct.
    // TODO: Reminder to use this pattern and clean up similar memory leaks.
    // TODO: use destroy instead of free for objects on heap, check all calls of free or destroy.
    output.init(wlr_output) catch |err| {
        log.err("Failed to create output: {s}", .{@errorName(err)});
        allocator.destroy(output);
        return;
    };
}

fn newXdgSurface(listener: *wl.Listener(*wlr.XdgSurface), xdg_surface: *wlr.XdgSurface) void {
    const self = @fieldParentPtr(Self, "new_xdg_surface", listener);
    log.debug("Signal: wlr_xdg_shell_new_surface", .{});
    if (xdg_surface.role == .toplevel) {
        if (self.seat.focused_output) |output| {
            XdgToplevel.init(output, xdg_surface) catch {
                log.err("Failed to allocate memory", .{});
                xdg_surface.resource.postNoMemory();
                return;
            };
        } else {
            log.err("No focused wlr_output found. Skipping xdg_toplevel.", .{});
            return;
        }
    }
}

// This callback is called when a new layer surface is created.
pub fn newLayerSurface(_: *wl.Listener(*wlr.LayerSurfaceV1), wlr_layer_surface: *wlr.LayerSurfaceV1) void {
    log.debug("Signal: wlr_layer_shell_new_surface", .{});
    log.debug(
        "New layer surface: namespace {s}, layer {s}, anchor {b:0>4}, size {},{}, margin {},{},{},{}, exclusive_zone {}",
        .{
            wlr_layer_surface.namespace,
            @tagName(wlr_layer_surface.pending.layer),
            @as(u32, @bitCast(wlr_layer_surface.pending.anchor)),
            wlr_layer_surface.pending.desired_width,
            wlr_layer_surface.pending.desired_height,
            wlr_layer_surface.pending.margin.top,
            wlr_layer_surface.pending.margin.right,
            wlr_layer_surface.pending.margin.bottom,
            wlr_layer_surface.pending.margin.left,
            wlr_layer_surface.pending.exclusive_zone,
        },
    );
    // TODO: Finish this.
}

// This callback is called when a new xwayland surface is created.
pub fn newXwaylandSurface(listener: *wl.Listener(*wlr.XwaylandSurface), xwayland_surface: *wlr.XwaylandSurface) void {
    _ = @fieldParentPtr(Self, "new_xwayland_surface", listener);
    log.debug("Signal: wlr_xwayland_new_surface", .{});

    if (xwayland_surface.override_redirect) {
        // TODO: Create override_redirect surface.
    } else {
        //TODO: Create Xwayland window.
    }
}

// Callback that gets triggered on existence of a new output.
fn setMode(listener: *wl.Listener(*wlr.OutputPowerManagerV1.event.SetMode), event: *wlr.OutputPowerManagerV1.event.SetMode) void {
    const self = @fieldParentPtr(Self, "set_mode", listener);
    const mode = event.mode == .on;
    const state = if (mode) "Enabling" else "Disabling";
    log.debug("Signal: wlr_output_power_manager_v1_set_mode", .{});
    log.debug(
        "{s} output {s}",
        .{
            state,
            event.output.name,
        },
    );

    event.output.enable(mode);
    event.output.commit() catch {
        log.err("Output commit failed: {s}", .{event.output.name});
        return;
    };

    // If the commit didn't fail then go ahead and edit the output_layout :)
    switch (event.mode) {
        .on => {
            if (self.output_layout.wlr_output_layout.get(event.output)) |_| {
                log.debug("Output is already in output_layout", .{});
            } else {
                log.debug("Adding output to output_layout", .{});
                self.output_layout.wlr_output_layout.addAuto(event.output);
            }
        },
        .off => {
            if (self.output_layout.wlr_output_layout.get(event.output)) |_| {
                self.output_layout.wlr_output_layout.remove(event.output);
            } else {
                log.debug("Output is already absent from the output_layout, not removing", .{});
            }
        },
        _ => {},
    }
}

fn logInfo() void {
    const uname_info = std.os.uname();
    log.info("System name: {s}", .{uname_info.sysname});
    log.info("Host name: {s}", .{uname_info.nodename});
    log.info("Release Info: {s}", .{uname_info.release});
    log.info("Version Info: {s}", .{uname_info.version});
}
