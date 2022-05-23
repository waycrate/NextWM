// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// herb/Server.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const std = @import("std");
const gpa = std.heap.c_allocator;

const View = @import("View.zig");
const Output = @import("Output.zig");
const c = @import("c.zig");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const default_cursor_size = 24;
const default_seat_name = "herbwm-seat0";

wl_server: *wl.Server,
wlr_backend: *wlr.Backend, // TODO: Support headless backend.
wlr_renderer: *wlr.Renderer,
wlr_allocator: *wlr.Allocator,
wlr_scene: *wlr.Scene,
wlr_compositor: *wlr.Compositor,

wlr_output_layout: *wlr.OutputLayout,
new_output: wl.Listener(*wlr.Output),

wlr_xdg_shell: *wlr.XdgShell,
new_xdg_surface: wl.Listener(*wlr.XdgSurface),
views: wl.list.Head(View, "link") = undefined,

wlr_seat: *wlr.Seat,
wlr_cursor: *wlr.Cursor,
wlr_xcursor_manager: *wlr.XcursorManager,

pub fn init(self: *Self) !void {
    // Creating the server itself.
    self.wl_server = try wl.Server.create();
    errdefer self.wl_server.destroy();

    // Determine the backend based on the current environment to render with such as opening an X11 window if an X11 server is running.
    // NOTE: This frees itself when the server is destroyed.
    self.wlr_backend = try wlr.Backend.autocreate(self.wl_server);

    // Determining the renderer based on the current environment.
    // Possible renderers: Pixman / GLES2 / Vulkan.
    self.wlr_renderer = try wlr.Renderer.autocreate(self.wlr_backend);
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
    // we use `.init` on the listener.
    self.new_output.setNotify(newOutput);
    self.wlr_backend.events.new_output.add(&self.new_output);

    // Add a callback for when new surfaces are created.
    //
    // zig only intializes structs with default value when using .{} notation. Since were not using that, we call `.setNotify`. In other instances
    // we use `.init` on the listener.
    self.new_xdg_surface.setNotify(newXdgSurface);
    self.wlr_xdg_shell.events.new_surface.add(&self.new_xdg_surface);
    self.views.init();
}

// Create the socket, start the backend, and setup the environment
pub fn start(self: *Self) !void {
    // We create a slice of 11 u8's ( practically a string buffer ) in which we store the socket value to be pushed later onto the env_map.
    var buf: [11]u8 = undefined;
    const socket = try self.wl_server.addSocketAuto(&buf);

    try self.wlr_backend.start();

    // Set the wayland_display environment variable.
    if (c.setenv("WAYLAND_DISPLAY", socket, 1) < 0) return error.SetenvError;
}

pub fn deinit(self: *Self) void {
    // Destroy all clients of the server.
    self.wl_server.destroyClients();

    self.wlr_backend.destroy();
    self.wlr_renderer.destroy();
    self.wlr_allocator.destroy();

    // Destroy the server.
    self.wl_server.destroy();
}

// Callback that gets triggered on existence of a new output.
pub fn newOutput(listener: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
    // Getting the server out of the listener. Field Parent Pointer - get a pointer to the parent struct from a field.
    const self = @fieldParentPtr(Self, "new_output", listener);

    // Configure the output created by the backend to use our allocator and renderer.
    if (!wlr_output.initRender(self.wlr_allocator, self.wlr_renderer)) return;

    // Some backends don't have modes. DRM+KMS does, and we need to set a mode before using the target.
    if (wlr_output.preferredMode()) |mode| {
        wlr_output.setMode(mode);
        wlr_output.enable(true);
        wlr_output.commit() catch return;
    }

    // Allocate memory to a new instance of output struct.
    const output = gpa.create(Output) catch {
        std.log.err("Failed to allocate new output", .{});
        return;
    };

    // Instantiate the output struct.
    output.* = .{
        .server = self,
        .wlr_output = wlr_output,
    };

    // Add a callback for the frame event from the output struct.
    //
    // Since we used .{} notation, the frame callback has been initialized so we don't need to call setNotify.
    wlr_output.events.frame.add(&output.frame);

    // Add the new output to the output_layout for automatic management by wlroots.
    self.wlr_output_layout.addAuto(wlr_output);
}

pub fn newXdgSurface(listener: *wl.Listener(*wlr.XdgSurface), xdg_surface: *wlr.XdgSurface) void {
    const self = @fieldParentPtr(Self, "new_xdg_surface", listener);

    switch (xdg_surface.role) {
        .toplevel => {
            const view = gpa.create(View) catch {
                std.log.err("Failed to allocate new view", .{});
                return;
            };

            view.* = .{
                .server = self,
                .xdg_surface = xdg_surface,
                .scene_node = self.wlr_scene.node.createSceneXdgSurface(xdg_surface) catch {
                    gpa.destroy(view);
                    std.log.err("Failed to allocate new view", .{});
                    return;
                },
            };
            view.scene_node.data = @ptrToInt(view);
            xdg_surface.data = @ptrToInt(view.scene_node);

            xdg_surface.events.map.add(&view.map);
            //xdg_surface.events.unmap.add(&view.unmap);
        },
        .popup => {
            // To be implemented soon.
        },
        .none => unreachable,
    }
}

pub fn focusView(self: *Self, view: *View, surface: *wlr.Surface) void {
    if (self.wlr_seat.keyboard_state.focused_surface) |previous_surface| {
        if (previous_surface == surface) return;
        if (previous_surface.isXdgSurface()) {
            const xdg_surface = wlr.XdgSurface.fromWlrSurface(previous_surface);
            _ = xdg_surface.role_data.toplevel.setActivated(false);
        }
    }

    view.scene_node.raiseToTop();
    view.link.remove();
    self.views.prepend(view);
    _ = view.xdg_surface.role_data.toplevel.setActivated(true);
}
