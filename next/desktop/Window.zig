// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// src/desktop/Window.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const Server = @import("../Server.zig");
const server = &@import("../next.zig").server;
const allocator = @import("../utils/allocator.zig").allocator;
const XdgToplevel = @import("XdgToplevel.zig");
const std = @import("std");
const log = std.log.scoped(.Window);

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const zwlr = @import("wayland").server.zwlr;

const Backend = union(enum) {
    xdg_toplevel: XdgToplevel,
};

server: *Server = server,

backend: Backend,
wlr_surface: ?*wlr.Surface = null,

map: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(map),

pub fn init(self: *Self, backend: Backend) void {
    // TODO: Set toplevel tags here.
    self.* = .{
        .backend = backend,
    };
}

pub fn map(listener: *wl.Listener(*wlr.XdgSurface), _: *wlr.XdgSurface) void {
    const self = @fieldParentPtr(Self, "map", listener);

    // Find index of self from pending_windows and remove it.
    if (std.mem.indexOfScalar(*Self, self.server.pending_windows.items, self)) |i| {
        _ = self.server.pending_windows.orderedRemove(i);

        self.server.mapped_windows.append(allocator, self) catch {
            log.err("Failed to allocate memory.", .{});
            return;
        };
    }
}
