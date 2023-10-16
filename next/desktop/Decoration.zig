// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/desktop/Decoration.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const allocator = @import("../utils/allocator.zig").allocator;
const log = std.log.scoped(.Decoration);
const server = &@import("../next.zig").server;
const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Window = @import("Window.zig");

xdg_toplevel_decoration: *wlr.XdgToplevelDecorationV1,

destroy: wl.Listener(*wlr.XdgToplevelDecorationV1) = wl.Listener(*wlr.XdgToplevelDecorationV1).init(handleDestroy),
request_mode: wl.Listener(*wlr.XdgToplevelDecorationV1) = wl.Listener(*wlr.XdgToplevelDecorationV1).init(requestMode),

pub fn init(self: *Self, xdg_toplevel_decoration: *wlr.XdgToplevelDecorationV1) void {
    self.* = .{ .xdg_toplevel_decoration = xdg_toplevel_decoration };
    log.debug("Intializing a toplevel decoration", .{});

    xdg_toplevel_decoration.events.destroy.add(&self.destroy);
    xdg_toplevel_decoration.events.request_mode.add(&self.request_mode);

    requestMode(&self.request_mode, self.xdg_toplevel_decoration);
}

fn handleDestroy(listener: *wl.Listener(*wlr.XdgToplevelDecorationV1), _: *wlr.XdgToplevelDecorationV1) void {
    const self = @fieldParentPtr(Self, "destroy", listener);
    log.debug("Signal: wlr_xdg_toplevel_decoration_destroy", .{});

    self.destroy.link.remove();
    self.request_mode.link.remove();

    const node = @fieldParentPtr(std.TailQueue(Self).Node, "data", self);
    server.decoration_manager.decorations.remove(node);
    allocator.destroy(node);
}

fn requestMode(listener: *wl.Listener(*wlr.XdgToplevelDecorationV1), _: *wlr.XdgToplevelDecorationV1) void {
    const self = @fieldParentPtr(Self, "request_mode", listener);
    log.debug("Signal: wlr_xdg_toplevel_decoration_request_mode", .{});

    const window = @as(*Window, @ptrFromInt(self.xdg_toplevel_decoration.surface.data));

    if (server.config.csdAllowed(window)) {
        _ = self.xdg_toplevel_decoration.setMode(.client_side);
    } else {
        _ = self.xdg_toplevel_decoration.setMode(.server_side);
    }
}
