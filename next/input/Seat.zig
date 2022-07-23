// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/input/Seat.zig
//
// Created by:	Aakash Sen Sharma, July 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const std = @import("std");
const allocator = @import("../utils/allocator.zig").allocator;
const log = std.log.scoped(.Seat);

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const server = &@import("../next.zig").server;
const Server = @import("../Server.zig");
const Output = @import("../desktop/Output.zig");

const default_seat_name: [*:0]const u8 = "next-seat0";

server: *Server = server,
wlr_seat: *wlr.Seat,

focused_output: *Output = undefined,

request_set_selection: wl.Listener(*wlr.Seat.event.RequestSetSelection) = wl.Listener(*wlr.Seat.event.RequestSetSelection).init(requestSetSelection),
request_set_primary_selection: wl.Listener(*wlr.Seat.event.RequestSetPrimarySelection) = wl.Listener(*wlr.Seat.event.RequestSetPrimarySelection).init(requestSetPrimarySelection),
request_set_cursor: wl.Listener(*wlr.Seat.event.RequestSetCursor) = wl.Listener(*wlr.Seat.event.RequestSetCursor).init(requestSetCursor),

pub fn init(self: *Self) !void {
    const seat = try wlr.Seat.create(server.wl_server, default_seat_name);
    self.* = .{ .wlr_seat = seat };
    self.wlr_seat.events.request_set_selection.add(&self.request_set_selection);
    self.wlr_seat.events.request_set_primary_selection.add(&self.request_set_primary_selection);
    self.wlr_seat.events.request_set_cursor.add(&self.request_set_cursor);
}

pub fn deinit(self: *Self) void {
    self.wlr_seat.destroy();
}

// Callback that gets triggered when the server seat wants to set a selection.
pub fn requestSetSelection(listener: *wl.Listener(*wlr.Seat.event.RequestSetSelection), event: *wlr.Seat.event.RequestSetSelection) void {
    const self = @fieldParentPtr(Self, "request_set_selection", listener);
    log.debug("Signal: wlr_seat_request_set_selection", .{});

    self.wlr_seat.setSelection(event.source, event.serial);
}

// Callback that gets triggered when the server seat wants to set the primary selection.
pub fn requestSetPrimarySelection(listener: *wl.Listener(*wlr.Seat.event.RequestSetPrimarySelection), event: *wlr.Seat.event.RequestSetPrimarySelection) void {
    const self = @fieldParentPtr(Self, "request_set_primary_selection", listener);
    log.debug("Signal: wlr_seat_request_set_primary_selection", .{});

    self.wlr_seat.setPrimarySelection(event.source, event.serial);
}

// Callback that gets triggered when a client wants to set the cursor image.
pub fn requestSetCursor(listener: *wl.Listener(*wlr.Seat.event.RequestSetCursor), event: *wlr.Seat.event.RequestSetCursor) void {
    const self = @fieldParentPtr(Self, "request_set_cursor", listener);
    log.debug("Signal: wlr_seat_request_set_cursor", .{});

    // Check if the client request to set the cursor is the currently focused surface.
    const focused_client = self.wlr_seat.pointer_state.focused_client;
    if (focused_client == event.seat_client) {
        log.debug("Focused toplevel set the cursor surface", .{});
        self.server.wlr_cursor.setSurface(event.surface, event.hotspot_x, event.hotspot_y);
    } else {
        log.debug("Non-focused toplevel attempted to set the cursor surface. Request denied", .{});
    }
}