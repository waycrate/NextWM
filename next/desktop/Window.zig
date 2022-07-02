// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// src/desktop/Window.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const Server = @import("../Server.zig");
const allocator = @import("../utils/allocator.zig").allocator;

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const zwlr = @import("wayland").server.zwlr;

server: *Server,
link: wl.list.Link = undefined,
xdg_surface: *wlr.XdgSurface,
scene_node: *wlr.SceneNode,
map: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(map),

pub fn map(listener: *wl.Listener(*wlr.XdgSurface), _: *wlr.XdgSurface) void {
    const window = @fieldParentPtr(Self, "map", listener);
    window.server.windows.append(allocator, window) catch {
        @panic("Failed to allocate memory.");
    };
    //view.server.focusView(view, xdg_surface.surface);
}
