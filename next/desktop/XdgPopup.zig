// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/desktop/XdgPopup.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const allocator = @import("../utils/allocator.zig").allocator;
const assert = std.debug.assert;
const log = std.log.scoped(.XdgPopup);
const server = &@import("../next.zig").server;
const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const XdgToplevel = @import("XdgToplevel.zig");
const Server = @import("../Server.zig");
const ParentSurface = union(enum) {
    xdg_toplevel: *XdgToplevel,
    xdg_popup: *Self,
};

wlr_xdg_popup: *wlr.XdgPopup,
parent: ParentSurface,

popups: std.ArrayListUnmanaged(*wlr.XdgPopup) = .{},
server: *Server = server,

//map: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(handleMap),
//unmap: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(handleUnmap),
//destroy: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(handleDestroy),
//new_popup: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(newPopup),

//commit: wl.Listener(*wlr.Surface) = wl.Listener(*wlr.Surface).init(handleCommit),

pub fn create(xdg_popup: *wlr.XdgPopup, parent: ParentSurface) ?*Self {
    const self: *Self = allocator.create(Self) catch {
        std.log.err("Failed to allocate memory", .{});
        xdg_popup.resource.postNoMemory();
        return null;
    };
    self.* = .{
        .parent = parent,
        .wlr_xdg_popup = xdg_popup,
    };

    if (xdg_popup.base.data == 0) xdg_popup.base.data = @ptrToInt(self);

    switch (parent) {
        // TODO: Finish this
        else => {},
    }
    return self;
}
