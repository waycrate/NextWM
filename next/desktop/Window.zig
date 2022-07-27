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

wlr_foreign_toplevel_handle: *wlr.ForeignToplevelHandleV1 = undefined,
backend: Backend,

pub fn init(self: *Self, output: *Output, backend: Backend) !void {
    log.debug("Initializing window", .{});
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

    switch (self.backend) {
        .xdg_toplevel => |xdg_toplevel| xdg_toplevel.xdg_surface.data = @ptrToInt(self),
    }
}

pub fn getAppId(self: *Self) [*:0]const u8 {
    log.debug("Surface AppID was requested", .{});
    return switch (self.backend) {
        .xdg_toplevel => |xdg_toplevel| xdg_toplevel.getAppId(),
    };
}

pub fn getTitle(self: *Self) [*:0]const u8 {
    log.debug("Surface Title was requested", .{});
    return switch (self.backend) {
        .xdg_toplevel => |xdg_toplevel| xdg_toplevel.getTitle(),
    };
}

pub fn notifyAppId(self: *Self, app_id: [*:0]const u8) void {
    log.debug("AppID data propagated to ftm handle", .{});
    self.wlr_foreign_toplevel_handle.setAppId(app_id);
}

pub fn notifyTitle(self: *Self, title: [*:0]const u8) void {
    log.debug("Title data propagated to ftm handle", .{});
    self.wlr_foreign_toplevel_handle.setTitle(title);
}
