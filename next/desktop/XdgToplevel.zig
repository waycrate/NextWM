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

window: *Window,

xdg_surface: *wlr.XdgSurface,
scene_node: *wlr.SceneNode,

// TODO: Some more toplevel listeners should go here.
set_app_id: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(setAppId),
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
    errdefer allocator.free(window);

    window.init(output, .{
        .xdg_toplevel = .{
            .window = window,
            .xdg_surface = xdg_surface,
            .scene_node = server.wlr_scene.node.createSceneXdgSurface(xdg_surface) catch {
                allocator.destroy(window);
                log.err("Failed to create scene_node out of xdg_surface", .{});
                return;
            },
        },
    }) catch {
        allocator.destroy(window);
        log.err("Failed to create a window out of the toplevel", .{});
        return;
    };

    xdg_surface.events.map.add(&window.map);
    xdg_surface.role_data.toplevel.events.set_app_id.add(&window.backend.xdg_toplevel.set_app_id);
    xdg_surface.role_data.toplevel.events.set_title.add(&window.backend.xdg_toplevel.set_title);
    // TODO:
    //xdg_surface.events.map.destroy(&self.destroy);
    //xdg_surface.events.map.new_popup(&self.new_popup);
    //xdg_surface.events.map.new_subsurface(&self.new_subsurface);
    //xdg_surface.events.map.unmap(&self.unmap);
    //
    //Handle existing subsurfaces.
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
