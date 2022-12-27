// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/desktop/XdgToplevel.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const allocator = @import("../utils/allocator.zig").allocator;
const log = std.log.scoped(.XdgToplevel);
const server = &@import("../next.zig").server;
const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Server = @import("../Server.zig");
const Window = @import("Window.zig");
const Output = @import("Output.zig");
const XdgPopup = @import("XdgPopup.zig");

window: *Window,

xdg_surface: *wlr.XdgSurface,

borders: std.ArrayListUnmanaged(*wlr.SceneRect) = .{},
popups: std.ArrayListUnmanaged(*XdgPopup) = .{},

geometry: wlr.Box = undefined,
draw_borders: bool = true,
scene_node: *wlr.SceneNode = undefined,
scene_surface: *wlr.SceneNode = undefined,

map: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(handleMap),
unmap: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(handleUnmap),
destroy: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(handleDestroy),
set_app_id: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(setAppId),
new_popup: wl.Listener(*wlr.XdgPopup) = wl.Listener(*wlr.XdgPopup).init(newPopup),
set_title: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(setTitle),

pub fn init(output: *Output, xdg_surface: *wlr.XdgSurface) error{OutOfMemory}!void {
    log.debug("New xdg_shell toplevel received: title={s} app_id={s}", .{
        xdg_surface.role_data.toplevel.title,
        xdg_surface.role_data.toplevel.app_id,
    });

    const window = allocator.create(Window) catch {
        log.err("Failed to allocate memory", .{});
        return;
    };
    errdefer allocator.destroy(window);

    window.init(output, .{ .xdg_toplevel = .{
        .window = window,
        .xdg_surface = xdg_surface,
    } }) catch {
        allocator.destroy(window);
        log.err("Failed to create a window out of the toplevel", .{});
        return;
    };

    xdg_surface.events.map.add(&window.backend.xdg_toplevel.map);
    xdg_surface.events.unmap.add(&window.backend.xdg_toplevel.unmap);
    xdg_surface.events.destroy.add(&window.backend.xdg_toplevel.destroy);
    xdg_surface.events.new_popup.add(&window.backend.xdg_toplevel.new_popup);

    xdg_surface.role_data.toplevel.events.set_app_id.add(&window.backend.xdg_toplevel.set_app_id);
    xdg_surface.role_data.toplevel.events.set_title.add(&window.backend.xdg_toplevel.set_title);
    // Maybe eventually we'll support these?
    // TODO: xdg_surface.events.map.new_subsurface(&self.new_subsurface);
    // TODO: Handle existing subsurfaces.
}

pub fn handleMap(listener: *wl.Listener(*wlr.XdgSurface), _: *wlr.XdgSurface) void {
    const self = @fieldParentPtr(Self, "map", listener);
    log.debug("Signal: wlr_xdg_surface_map", .{});

    // TODO: Check if view wants to be fullscreen then make it fullscreen.

    // Setting some struct fields we will need later
    self.scene_node = &(server.layer_tile.createSceneTree() catch return).node;
    self.scene_surface = self.scene_node.createSceneXdgSurface(self.xdg_surface) catch return;
    self.xdg_surface.getGeometry(&self.geometry);

    // Looping over 4 times to create the top, bottom, left, and right borders.
    var j: usize = 0;
    while (j <= 4) : (j += 1) {
        self.borders.append(allocator, self.scene_node.createSceneRect(0, 0, &server.config.border_color) catch return) catch return;
    }

    // If the client can have csd then why draw servide side borders?
    if (server.config.csdAllowed(self.window)) {
        self.draw_borders = false;
    } else {
        _ = self.xdg_surface.role_data.toplevel.setTiled(.{ .top = true, .bottom = true, .left = true, .right = true });
    }

    self.resize(self.geometry.x, self.geometry.y, self.geometry.width, self.geometry.height);

    self.window.wlr_foreign_toplevel_handle = wlr.ForeignToplevelHandleV1.create(server.wlr_foreign_toplevel_manager) catch {
        log.err("Failed to create foreign_toplevel_handle", .{});
        return;
    };

    // Setup ftm handle listeners.
    // TODO: Some more toplevel handle listeners go here
    self.window.wlr_foreign_toplevel_handle.setTitle(self.getTitle());
    self.window.wlr_foreign_toplevel_handle.setAppId(self.getAppId());

    // TODO: This segfaults probably because we infer wlr_output from the seats currently focused output which is initially undefined
    // TODO: Fix me
    // self.window.wlr_foreign_toplevel_handle.outputEnter(self.window.output.wlr_output);

    // Find index of self from pending_windows and remove it.
    if (std.mem.indexOfScalar(*Window, server.pending_windows.items, self.window)) |i| {
        _ = server.pending_windows.orderedRemove(i);
    }

    // Appending should happen regardless of us finding the window in pending_windows.
    server.mapped_windows.append(allocator, self.window) catch {
        log.err("Failed to allocate memory.", .{});
        self.xdg_surface.resource.getClient().postNoMemory();
        return;
    };
    log.debug("Window '{s}' mapped", .{self.getTitle()});
}

pub fn newPopup(listener: *wl.Listener(*wlr.XdgPopup), xdg_popup: *wlr.XdgPopup) void {
    const self = @fieldParentPtr(Self, "new_popup", listener);
    log.debug("Signal: wlr_xdg_surface_new_popup", .{});

    if (XdgPopup.create(xdg_popup, .{ .xdg_toplevel = self })) |popup| {
        self.popups.append(allocator, popup) catch return;
    }
}

pub fn handleUnmap(listener: *wl.Listener(*wlr.XdgSurface), _: *wlr.XdgSurface) void {
    const self = @fieldParentPtr(Self, "unmap", listener);
    log.debug("Signal: wlr_xdg_surface_unmap", .{});

    if (std.mem.indexOfScalar(*Window, server.mapped_windows.items, self.window)) |i| {
        _ = server.mapped_windows.orderedRemove(i);
    }
    if (server.seat.wlr_seat.keyboard_state.focused_surface) |focused_surface| {
        if (focused_surface == self.xdg_surface.surface) {
            server.seat.wlr_seat.keyboardClearFocus();
        }
    }
    if (server.seat.wlr_seat.pointer_state.focused_surface) |focused_surface| {
        if (focused_surface == self.xdg_surface.surface) {
            server.seat.wlr_seat.keyboardClearFocus();
        }
    }
}

pub fn handleDestroy(listener: *wl.Listener(*wlr.XdgSurface), _: *wlr.XdgSurface) void {
    const self = @fieldParentPtr(Self, "destroy", listener);
    log.debug("Signal: wlr_xdg_surface_destroy", .{});

    self.window.handleDestroy();
}

pub fn resize(self: *Self, x: c_int, y: c_int, width: c_int, height: c_int) void {
    const border_width = server.config.border_width;
    self.geometry.x = x;
    self.geometry.y = y;
    self.geometry.width = width;
    self.geometry.height = height;

    if (self.draw_borders) {
        // If borders are meant to be drawn then add that to the geometry width
        self.geometry.width += 2 * border_width;
        self.geometry.height += 2 * border_width;

        self.borders.items[0].setSize(self.geometry.width, border_width);

        self.borders.items[1].setSize(self.geometry.width, border_width);
        self.borders.items[1].node.setPosition(0, self.geometry.height - border_width);

        self.borders.items[2].setSize(border_width, self.geometry.height - 2 * border_width);
        self.borders.items[2].node.setPosition(0, border_width);

        self.borders.items[3].setSize(border_width, self.geometry.height - 2 * border_width);
        self.borders.items[3].node.setPosition(self.geometry.width - border_width, border_width);
    }
    self.scene_node.setPosition(self.geometry.x, self.geometry.y);
    self.scene_surface.setPosition(border_width, border_width);

    _ = self.xdg_surface.role_data.toplevel.setSize(@intCast(u32, width), @intCast(u32, height));
}

pub fn setAppId(listener: *wl.Listener(*wlr.XdgSurface), _: *wlr.XdgSurface) void {
    const self = @fieldParentPtr(Self, "set_app_id", listener);
    log.debug("Signal: wlr_xdg_toplevel_set_app_id", .{});

    self.window.notifyAppId(self.getAppId());
}

pub fn setTitle(listener: *wl.Listener(*wlr.XdgSurface), _: *wlr.XdgSurface) void {
    const self = @fieldParentPtr(Self, "set_title", listener);
    log.debug("Signal: wlr_xdg_toplevel_set_title", .{});

    self.window.notifyTitle(self.getTitle());
}

pub fn getTitle(self: Self) [*:0]const u8 {
    if (self.xdg_surface.role_data.toplevel.title) |title| {
        return title;
    } else {
        return "<No Title>";
    }
}

pub fn getAppId(self: Self) [*:0]const u8 {
    if (self.xdg_surface.role_data.toplevel.app_id) |app_id| {
        return app_id;
    } else {
        return "<No AppId>";
    }
}
