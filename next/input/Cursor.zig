// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/input/Cursor.zig
//
// Created by:	Aakash Sen Sharma, July 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const std = @import("std");
const allocator = @import("../utils/allocator.zig").allocator;
const server = &@import("../next.zig").server;
const log = std.log.scoped(.Cursor);

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Server = @import("../Server.zig");

server: *Server,

wlr_input_device: *wlr.InputDevice,
pointer_destroy: wl.Listener(*wlr.InputDevice) = wl.Listener(*wlr.InputDevice).init(pointerDestroy),
request_set_cursor: wl.Listener(*wlr.Seat.event.RequestSetCursor) = wl.Listener(*wlr.Seat.event.RequestSetCursor).init(requestSetCursor),

pub fn init(self: *Self, device: *wlr.InputDevice) void {
    log.debug("Initializing pointer device", .{});
    self.* = .{
        .server = server,
        .wlr_input_device = device,
    };
    self.server.cursors.append(allocator, self) catch {
        log.err("Failed to allocate memory", .{});
        return;
    };

    self.wlr_input_device.events.destroy.add(&self.pointer_destroy);
    self.server.seat.wlr_seat.events.request_set_cursor.add(&self.request_set_cursor);
}

fn pointerDestroy(listener: *wl.Listener(*wlr.InputDevice), input_device: *wlr.InputDevice) void {
    const self = @fieldParentPtr(Self, "pointer_destroy", listener);
    log.debug("Signal: wlr_input_device_destroy (pointer)", .{});
    self.server.wlr_cursor.detachInputDevice(input_device);
}

// Callback that gets triggered when a client wants to set the cursor image.
pub fn requestSetCursor(listener: *wl.Listener(*wlr.Seat.event.RequestSetCursor), event: *wlr.Seat.event.RequestSetCursor) void {
    const self = @fieldParentPtr(Self, "request_set_cursor", listener);
    log.debug("Signal: wlr_seat_request_set_cursor", .{});

    // Check if the client request to set the cursor is the currently focused surface.
    const focused_client = self.server.seat.wlr_seat.pointer_state.focused_client;
    if (focused_client == event.seat_client) {
        log.debug("Focused toplevel set the cursor surface", .{});
        self.server.wlr_cursor.setSurface(event.surface, event.hotspot_x, event.hotspot_y);
    } else {
        log.debug("Non-focused toplevel attempted to set the cursor surface. Request denied", .{});
    }
}
