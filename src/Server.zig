// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// src/Server.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const std = @import("std");

pub const allocator = std.heap.c_allocator; // zig has no default memory allocator unlike c (malloc, realloc, free) , so we use c_allocator while linking against libc.
const Window = @import("Window.zig");
const Output = @import("Output.zig");
const c = @import("c.zig");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const default_cursor_size = 24;
const default_seat_name = "herb-seat0";

wl_server: *wl.Server,
wl_event_loop: *wl.EventLoop,
wlr_backend: *wlr.Backend,
wlr_headless_backend: *wlr.Backend,
wlr_renderer: *wlr.Renderer,
wlr_allocator: *wlr.Allocator,
wlr_scene: *wlr.Scene,
wlr_compositor: *wlr.Compositor,

sigint_cb: *wl.EventSource,
sigterm_cb: *wl.EventSource,
sigkill_cb: *wl.EventSource,
sigabrt_cb: *wl.EventSource,
sigquit_cb: *wl.EventSource,

wlr_output_layout: *wlr.OutputLayout,
new_output: wl.Listener(*wlr.Output),

wlr_xdg_shell: *wlr.XdgShell,
new_xdg_surface: wl.Listener(*wlr.XdgSurface),
windows: std.ArrayListUnmanaged(*Window),

wlr_seat: *wlr.Seat,
wlr_cursor: *wlr.Cursor,
wlr_xcursor_manager: *wlr.XcursorManager,

wlr_xwayland: *wlr.Xwayland,

pub fn init(self: *Self) !void {
    // Creating the server itself.
    self.wl_server = try wl.Server.create();
    errdefer self.wl_server.destroy();

    // Incorporate signal handling into the wayland event loop.
    self.wl_event_loop = self.wl_server.getEventLoop();
    self.sigabrt_cb = try self.wl_event_loop.addSignal(*wl.Server, std.os.SIG.ABRT, terminateCb, self.wl_server);
    self.sigint_cb = try self.wl_event_loop.addSignal(*wl.Server, std.os.SIG.INT, terminateCb, self.wl_server);
    self.sigquit_cb = try self.wl_event_loop.addSignal(*wl.Server, std.os.SIG.QUIT, terminateCb, self.wl_server);
    self.sigterm_cb = try self.wl_event_loop.addSignal(*wl.Server, std.os.SIG.TERM, terminateCb, self.wl_server);

    // Determine the backend based on the current environment to render with such as opening an X11 window if an X11 server is running.
    // NOTE: This frees itself when the server is destroyed.
    self.wlr_backend = try wlr.Backend.autocreate(self.wl_server);

    // Created when no ouputs are available.
    // NOTE: This frees itself when server is destroyed.
    self.wlr_headless_backend = try wlr.Backend.createHeadless(self.wl_server);

    // Creating the renderer.
    const drm_fd = self.wlr_backend.getDrmFd();
    if (drm_fd < 0) {
        @panic("Couldn't query DRM_FD.");
    }
    //TODO: Utilize this and write the opengl backend.
    self.wlr_renderer = try wlr.Renderer.createWithDrmFd(drm_fd);
    errdefer self.wlr_renderer.destroy();

    // Autocreate an allocator. An allocator acts as a bridge between the renderer and the backend allowing us to render to the screen by handling buffer creation.
    self.wlr_allocator = try wlr.Allocator.autocreate(self.wlr_backend, self.wlr_renderer);
    errdefer self.wlr_allocator.destroy();

    // Create the compositor from the server and renderer.
    self.wlr_compositor = try wlr.Compositor.create(self.wl_server, self.wlr_renderer);

    // Creating a scene graph. This handles the servers rendering and damage tracking.
    self.wlr_scene = try wlr.Scene.create();

    // Create an output layout to work with the physical arrangement of screens.
    self.wlr_output_layout = try wlr.OutputLayout.create();
    errdefer self.wlr_output_layout.destroy();

    // Creating a xdg_shell which is a wayland protocol for application windows.
    self.wlr_xdg_shell = try wlr.XdgShell.create(self.wl_server);

    //Configures a seat, which is a single "seat" at which a user sits and
    //operates the computer. This conceptually includes up to one keyboard,
    //pointer, touch, and drawing tablet device. We also rig up a listener to
    //let us know when new input devices are available on the backend.
    self.wlr_seat = try wlr.Seat.create(self.wl_server, default_seat_name);
    errdefer self.wlr_seat.destroy();

    // Create a wlr cursor object which is a wlroots utility to track the cursor on the screen.
    self.wlr_cursor = try wlr.Cursor.create();
    errdefer self.wlr_cursor.destroy();

    // Create a Xcursor manager which loads up xcursor themes on all scale factors. We pass null for theme name and 24 for the cursor size.
    self.wlr_xcursor_manager = try wlr.XcursorManager.create(null, default_cursor_size);
    errdefer self.wlr_xcursor_manager.destroy();

    // Initialize wl_shm, linux-dmabuf and other buffer factory protocols.
    try self.wlr_renderer.initServer(self.wl_server);

    // Attach the output layout to the scene graph so we get automatic damage tracking.
    try self.wlr_scene.attachOutputLayout(self.wlr_output_layout);

    // NOTE: These all free themselves when wlr_server is destroy.
    // Create the data device manager from the server, this generally handles the input events such as keyboard, mouse, touch etc.
    _ = try wlr.DataDeviceManager.create(self.wl_server);
    _ = try wlr.DataControlManagerV1.create(self.wl_server);
    _ = try wlr.ExportDmabufManagerV1.create(self.wl_server);
    _ = try wlr.GammaControlManagerV1.create(self.wl_server);
    _ = try wlr.ScreencopyManagerV1.create(self.wl_server);
    _ = try wlr.Viewporter.create(self.wl_server);

    // Assign the new output callback to said event.
    //
    // zig only intializes structs with default value when using .{} notation. Since were not using that, we call `.setNotify`. In other instances
    // we use `.init` on the listener declaration directly.
    self.new_output.setNotify(newOutput);
    self.wlr_backend.events.new_output.add(&self.new_output);

    // Add a callback for when new surfaces are created.
    //
    // zig only intializes structs with default value when using .{} notation. Since were not using that, we call `.setNotify`. In other instances
    // we use `.init` on the listener declaration directly.
    self.new_xdg_surface.setNotify(newXdgSurface);
    self.wlr_xdg_shell.events.new_surface.add(&self.new_xdg_surface);

    // Initializing Xwayland.
    // True here indicates that Xwayland will be launched on demand.
    self.wlr_xwayland = try wlr.Xwayland.create(self.wl_server, self.wlr_compositor, true);
    self.wlr_xwayland.setSeat(self.wlr_seat);
}

// Create the socket, start the backend, and setup the environment
pub fn start(self: *Self) !void {
    // We create a slice of 11 u8's ( practically a string buffer ) in which we store the socket value to be pushed later onto the env_map.
    var buf: [11]u8 = undefined;
    const socket = try self.wl_server.addSocketAuto(&buf);

    // Set the wayland_display environment variable.
    if (c.setenv("WAYLAND_DISPLAY", socket, 1) < 0) return error.SetenvError;
    if (c.setenv("DISPLAY", self.wlr_xwayland.display_name, 1) < 0) return error.SetenvError;

    try self.wlr_backend.start();
}

// This is called to gracefully handle signals.
fn terminateCb(_: c_int, wl_server: *wl.Server) callconv(.C) c_int {
    wl_server.terminate();
    return 0;
}

pub fn deinit(self: *Self) void {
    // Destroy all clients of the server.
    self.wl_server.destroyClients();

    self.sigabrt_cb.remove();
    self.sigint_cb.remove();
    self.sigquit_cb.remove();
    self.sigterm_cb.remove();

    self.wlr_xwayland.destroy();
    self.wlr_cursor.destroy();
    self.wlr_xcursor_manager.destroy();
    self.wlr_output_layout.destroy();
    self.wlr_seat.destroy();
    self.wlr_renderer.destroy();
    self.wlr_allocator.destroy();
    self.wlr_backend.destroy();

    // Destroy the server.
    self.wl_server.destroy();
}

// Callback that gets triggered on existence of a new output.
pub fn newOutput(_: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
    // Getting the server out of the listener. Field Parent Pointer - get a pointer to the parent struct from a field.
    // TODO: push to outputlist: const self = @fieldParentPtr(Self, "new_output", listener);

    // Allocate memory to a new instance of output struct.
    const output = allocator.create(Output) catch {
        std.log.err("Failed to allocate new output", .{});
        return;
    };

    // Instantiate the output struct.
    output.init(wlr_output);
}

// This callback is called when a new xdg toplevel is created ( xdg toplevels are basically application windows. )
pub fn newXdgSurface(listener: *wl.Listener(*wlr.XdgSurface), xdg_surface: *wlr.XdgSurface) void {
    // Getting the server out of the listener. Field Parent Pointer - get a pointer to the parent struct from a field.
    const self = @fieldParentPtr(Self, "new_xdg_surface", listener);

    // The role of the surface can be of 2 types:
    // - xdg_toplevel
    // - xdg_popup
    //
    // Popups include context menus and other floating windows that are in respect to any particular toplevel.
    // We only want to manage toplevel here, popups will be managed separately.
    if (xdg_surface.role == .toplevel) {
        // Allocate enough memory for the "Window" object
        const window = allocator.create(Window) catch {
            std.log.err("Failed to allocate new view", .{});
            return;
        };

        // Populating the window struct with it's members.
        window.* = .{
            .server = self,
            .xdg_surface = xdg_surface,
            // wlr scene graph API is a simple API that gives us damage tracking for free.
            // A.K.A less work to do, so we simply use it.
            // If you don't know what damage tracking is -> https://emersion.fr/blog/2019/intro-to-damage-tracking/
            // NOTE: We mght need to switch over from scene_node to manual rendering for opengl backend.
            // If you're wondering what that's for, it'll basically exist to provide sexy dual kawase blur.
            .scene_node = self.wlr_scene.node.createSceneXdgSurface(xdg_surface) catch {
                // If we fail then the free the memory we allocated earlier.
                allocator.destroy(window);
                std.log.err("Failed to allocate new view", .{});
                return;
            },
        };
        window.scene_node.data = @ptrToInt(window);
        xdg_surface.data = @ptrToInt(window.scene_node);

        xdg_surface.events.map.add(&window.map);
        //xdg_surface.events.unmap.add(&view.unmap);
    }
}
