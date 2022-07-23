// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/desktop/Window.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const allocator = @import("../utils/allocator.zig").allocator;
const assert = std.debug.assert;
const log = std.log.scoped(.Window);
const server = &@import("../next.zig").server;
const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Server = @import("../Server.zig");
const Output = @import("Output.zig");
const XdgToplevel = @import("XdgToplevel.zig");

const Backend = union(enum) {
    xdg_toplevel: XdgToplevel,
};

server: *Server = server,
output: *Output,

wlr_foreign_toplevel_handle: *wlr.ForeignToplevelHandleV1 = null,

backend: Backend,
wlr_surface: ?*wlr.Surface = null,

map: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(map),

pub fn init(self: *Self, output: *Output, backend: Backend) !void {
    // TODO: Set toplevel tags here.
    self.* = .{
        .output = output,
        .backend = backend,
        .wlr_foreign_toplevel_handle = try wlr.ForeignToplevelHandleV1.create(server.wlr_foreign_toplevel_manager),
    };

    server.pending_windows.append(allocator, self) catch {
        log.err("Failed to allocate memory", .{});
        return;
    };

    switch (backend) {
        .xdg_toplevel => |xdg_toplevel| xdg_toplevel.xdg_surface.data = @ptrToInt(self),
    }
}

pub fn map(listener: *wl.Listener(*wlr.XdgSurface), _: *wlr.XdgSurface) void {
    const self = @fieldParentPtr(Self, "map", listener);
    log.debug("Window '{s}' mapped", .{self.getTitle()});

    self.wlr_foreign_toplevel_handle.setTitle(self.getTitle());
    self.wlr_foreign_toplevel_handle.setAppId(self.getAppId());

    // Find index of self from pending_windows and remove it.
    if (std.mem.indexOfScalar(*Self, self.server.pending_windows.items, self)) |i| {
        _ = self.server.pending_windows.orderedRemove(i);
    }

    // Appending should happen regardless of us finding the window in pending_windows.
    self.server.mapped_windows.append(allocator, self) catch {
        log.err("Failed to allocate memory.", .{});
        return;
    };
}

pub fn getAppId(self: Self) [*:0]const u8 {
    return switch (self.backend) {
        .xdg_toplevel => |xdg_toplevel| xdg_toplevel.getAppId(),
    };
}

pub fn getTitle(self: Self) [*:0]const u8 {
    return switch (self.backend) {
        .xdg_toplevel => |xdg_toplevel| xdg_toplevel.getTitle(),
    };
}

pub fn notifyAppId(self: Self, app_id: [*:0]const u8) void {
    self.wlr_foreign_toplevel_handle.setAppId(app_id);
}

pub fn notifyTitle(self: Self, title: [*:0]const u8) void {
    self.wlr_foreign_toplevel_handle.setTitle(title);
}
