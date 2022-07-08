// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/desktop/DecorationManager.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const allocator = @import("../utils/allocator.zig").allocator;
const log = std.log.scoped(.DecorationManager);
const server = &@import("../next.zig").server;
const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Decoration = @import("Decoration.zig");

decorations: std.TailQueue(Decoration) = .{},

xdg_decoration_manager: *wlr.XdgDecorationManagerV1,

new_toplevel_decoration: wl.Listener(*wlr.XdgToplevelDecorationV1) = wl.Listener(*wlr.XdgToplevelDecorationV1).init(newToplevelDecoration),

pub fn init(self: *Self) !void {
    self.* = .{
        .xdg_decoration_manager = try wlr.XdgDecorationManagerV1.create(server.wl_server),
    };
    self.xdg_decoration_manager.events.new_toplevel_decoration.add(&self.new_toplevel_decoration);
}

fn newToplevelDecoration(listener: *wl.Listener(*wlr.XdgToplevelDecorationV1), xdg_toplevel_decoration: *wlr.XdgToplevelDecorationV1) void {
    log.debug("Signal: wlr_xdg_decoration_manager_new_toplevel_decoration", .{});

    const self = @fieldParentPtr(Self, "new_toplevel_decoration", listener);
    const decoration = allocator.create(std.TailQueue(Decoration).Node) catch {
        xdg_toplevel_decoration.resource.postNoMemory();
        return;
    };
    decoration.data.init(xdg_toplevel_decoration);
    self.decorations.append(decoration);
}
