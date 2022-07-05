// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/desktop/XdgToplevel.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const std = @import("std");

const Window = @import("Window.zig");
const Server = @import("../Server.zig");
const server = &@import("../next.zig").server;
const allocator = @import("../utils/allocator.zig").allocator;

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const log = std.log.scoped(.XdgToplevel);

server: *Server,

window: *Window,
xdg_surface: *wlr.XdgSurface,
scene_node: *wlr.SceneNode,
// TODO: Some toplevel listeners go here.

pub fn init(xdg_surface: *wlr.XdgSurface) error{OutOfMemory}!void {
    log.debug("New xdg_shell toplevel received: title={s} app_id={s}", .{
        xdg_surface.role_data.toplevel.title,
        xdg_surface.role_data.toplevel.app_id,
    });

    const window = allocator.create(Window) catch {
        log.err("Failed to allocate memory", .{});
        return;
    };
    errdefer allocator.free(window);

    const self = .{
        .server = server,
        .window = window,
        .xdg_surface = xdg_surface,
        .scene_node = server.wlr_scene.node.createSceneXdgSurface(xdg_surface) catch {
            allocator.destroy(window);
            log.err("Failed to create scene_node out of xdg_surface", .{});
            return;
        },
    };
    xdg_surface.data = @ptrToInt(&self);

    window.init(.{
        .xdg_toplevel = self,
    });
    self.server.pending_windows.append(allocator, window) catch {
        @panic("Failed to allocate memory");
    };

    xdg_surface.events.map.add(&window.map);
    // TODO:
    //xdg_surface.events.map.destroy(&self.destroy);
    //xdg_surface.events.map.new_popup(&self.new_popup);
    //xdg_surface.events.map.new_subsurface(&self.new_subsurface);
    //xdg_surface.events.map.unmap(&self.unmap);
    //
    //Handle existing subsurfaces.
}
