// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/desktop/DecorationManager.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const std = @import("std");
const server = &@import("../next.zig").server;
const log = std.log.scoped(.DecorationManager);

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

xdg_decoration_manager: *wlr.XdgDecorationManagerV1,

new_toplevel_decoration: wl.Listener(*wlr.XdgToplevelDecorationV1) = wl.Listener(*wlr.XdgToplevelDecorationV1).init(newToplevelDecoration),

pub fn init(self: *Self) !void {
    self.* = .{
        .xdg_decoration_manager = try wlr.XdgDecorationManagerV1.create(server.wl_server),
    };
    self.xdg_decoration_manager.events.new_toplevel_decoration.add(&self.new_toplevel_decoration);
}

// We should probably store all toplevel_decorations in an arraylist or tailqueue to update them later on demand.
fn newToplevelDecoration(_: *wl.Listener(*wlr.XdgToplevelDecorationV1), xdg_toplevel_decoration: *wlr.XdgToplevelDecorationV1) void {
    log.debug("Signal: wlr_xdg_decoration_manager_new_toplevel_decoration", .{});
    _ = xdg_toplevel_decoration.setMode(.server_side);
}
