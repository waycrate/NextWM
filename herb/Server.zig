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
backend: *wlr.Backend, // TODO: Support headless backend.
renderer: *wlr.Renderer,
allocator: *wlr.Allocator,
scene: *wlr.Scene,

output_layout: *wlr.OutputLayout,
new_output: wl.Listener(*wlr.Output) = wl.Listener(*wlr.Output).init(newOutput),

xdg_shell: *wlr.XdgShell,
new_xdg_surface: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(newXdgSurface),
views: wl.list.Head(View, "link") = undefined,

seat: *wlr.Seat,
cursor: *wlr.Cursor,
cursor_manager: *wlr.XcursorManager,

pub fn init(self: *Self) !void {
    // Creating the server itself.
    const wl_server = try wl.Server.create();

    // Determine the backend based on the current environment to render with such as opening an X11 window if an X11 server is running.
    const backend = try wlr.Backend.autocreate(wl_server);

    // Determining the renderer based on the current environment.
    // Possible renderers: Pixman / GLES2 / Vulkan.
    const renderer = try wlr.Renderer.autocreate(backend);

    // Autocreate an allocator. An allocator acts as a bridge between the renderer and the backend allowing us to render to the screen by handling buffer creation.
    const allocator = try wlr.Allocator.autocreate(backend, renderer);

    // Creating a scene graph. This handles the servers rendering and damage tracking.
    const scene = try wlr.Scene.create();

    // Create an output layout to work with the physical arrangement of screens.
    const output_layout = try wlr.OutputLayout.create();

    // Creating a xdg_shell which is a wayland protocol for application windows.
    const xdg_shell = try wlr.XdgShell.create(wl_server);

    //Configures a seat, which is a single "seat" at which a user sits and
    //operates the computer. This conceptually includes up to one keyboard,
    //pointer, touch, and drawing tablet device. We also rig up a listener to
    //let us know when new input devices are available on the backend.
    const seat = try wlr.Seat.create(wl_server, default_seat_name);

    // Create a wlr cursor object which is a wlroots utility to track the cursor on the screen.
    const cursor = try wlr.Cursor.create();

    // Create a Xcursor manager which loads up xcursor themes on all scale factors. We pass null for theme name and 24 for the cursor size.
    const cursor_manager = try wlr.XcursorManager.create(null, default_cursor_size);

    // Initiazlize the renderer with respect to our server.
    try renderer.initServer(wl_server);

    // Attach the output layout to the scene graph so we get automatic damage tracking.
    try scene.attachOutputLayout(output_layout);

    // Create the compositor from the server and renderer.
    _ = try wlr.Compositor.create(wl_server, renderer);

    // Create the data device manager from the server, this generally handles the input events such as keyboard, mouse, touch etc.
    _ = try wlr.DataDeviceManager.create(wl_server);

    // Populating the server struct with our data.
    self.* = .{
        .wl_server = wl_server,
        .backend = backend,
        .renderer = renderer,
        .allocator = allocator,
        .scene = scene,

        .output_layout = output_layout,
        .xdg_shell = xdg_shell,
        .seat = seat,
        .cursor = cursor,
        .cursor_manager = cursor_manager,
    };

    // Assign the new output callback to said event.
    self.backend.events.new_output.add(&self.new_output);

    // Add a callback for when new surfaces are created.
    self.xdg_shell.events.new_surface.add(&self.new_xdg_surface);
    self.views.init();
}

// Create the socket, start the backend, and setup the environment
pub fn start(self: Self) !void {
    // We create a slice of 11 u8's ( practically a string buffer ) in which we store the socket value to be pushed later onto the env_map.
    var buf: [11]u8 = undefined;
    const socket = try self.wl_server.addSocketAuto(&buf);

    try self.backend.start();

    // Set the wayland_display environment variable.
    if (c.setenv("WAYLAND_DISPLAY", socket, 1) < 0) return error.SetenvError;
}

pub fn deinit(self: *Self) void {
    // Destroy all clients of the server.
    self.wl_server.destroyClients();

    // Destroy the server.
    self.wl_server.destroy();
}

// Callback that gets triggered on existence of a new output.
pub fn newOutput(listener: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
    // Getting the server out of the listener. Field Parent Pointer - get a pointer to the parent struct from a field.
    const self = @fieldParentPtr(Self, "new_output", listener);

    // Configure the output created by the backend to use our allocator and renderer.
    if (!wlr_output.initRender(self.allocator, self.renderer)) return;

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
    wlr_output.events.frame.add(&output.frame);

    // Add the new output to the output_layout for automatic management by wlroots.
    self.output_layout.addAuto(wlr_output);
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
                .scene_node = self.scene.node.createSceneXdgSurface(xdg_surface) catch {
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
    if (self.seat.keyboard_state.focused_surface) |previous_surface| {
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
