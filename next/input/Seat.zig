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
const Window = @import("../desktop/Window.zig");
const Output = @import("../desktop/Output.zig");

const default_seat_name: [*:0]const u8 = "next-seat0";
const FocusTarget = union(enum) {
    window: *Window,
    none: void,
};

server: *Server,
wlr_seat: *wlr.Seat,

// Flag to denote any on-going pointer-drags.
pointer_drag: bool = false,

// Currently focused wl_output
focused_output: ?*Output = null,

// Currently focused window.
focused_window: FocusTarget = .none,

request_set_selection: wl.Listener(*wlr.Seat.event.RequestSetSelection) = wl.Listener(*wlr.Seat.event.RequestSetSelection).init(requestSetSelection),
request_set_primary_selection: wl.Listener(*wlr.Seat.event.RequestSetPrimarySelection) = wl.Listener(*wlr.Seat.event.RequestSetPrimarySelection).init(requestSetPrimarySelection),
request_start_drag: wl.Listener(*wlr.Seat.event.RequestStartDrag) = wl.Listener(*wlr.Seat.event.RequestStartDrag).init(requestStartDrag),

request_set_cursor: wl.Listener(*wlr.Seat.event.RequestSetCursor) = wl.Listener(*wlr.Seat.event.RequestSetCursor).init(requestSetCursor),

/// Memory allocated for the seat is free'd from the deinit call.
pub fn init(self: *Self) !void {
    const seat = try wlr.Seat.create(server.wl_server, default_seat_name);
    self.* = .{
        .wlr_seat = seat,
        .server = server,
    };

    self.wlr_seat.events.request_set_cursor.add(&self.request_set_cursor);
    self.wlr_seat.events.request_set_primary_selection.add(&self.request_set_primary_selection);
    self.wlr_seat.events.request_set_selection.add(&self.request_set_selection);
}

pub fn deinit(self: *Self) void {
    self.wlr_seat.destroy();
    allocator.destroy(self);
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

pub fn requestStartDrag(listener: *wl.Listener(*wlr.Seat.event.RequestStartDrag), event: *wlr.Seat.event.RequestStartDrag) void {
    const self = @fieldParentPtr(Self, "request_start_drag", listener);
    log.debug("Signal: wlr_seat_request_start_drag", .{});

    if (!self.wlr_seat.validatePointerGrabSerial(event.origin, event.serial)) {
        log.err("Failed to validate pointer serial {}", .{event.serial});
        if (event.drag.source) |source| source.destroy();
        return;
    }

    if (self.pointer_drag) {
        log.debug("Ignoring drag request, another pointer drag is currently in progress", .{});
        return;
    }

    log.debug("Starting pointer drag", .{});
    self.wlr_seat.startPointerDrag(event.drag, event.serial);
}

pub fn setFocus(self: *Self, window: *Window) void {
    //TODO: On switching tty's keyboards are destroyed and hence leave the surface, when we switch back to the compositor, the keyboard is recreated
    //TODO: and events are sent apart from enter event, which is a violation of wayland protocol, so fix that.
    //TODO: https://github.com/riverwm/river/commit/d4b2f2b0fc5766c8ae14a6f42fe76d058bfb3505
    // If currently focused surface is a layer then we don't want other apps to get the focus :)
    if (self.focused == .layer) return;

    if (window.output != self.focused_output) self.focusOutput(window.output);
    //TODO: Finish this.
}

pub fn focusOutput(self: *Self, output: *Output) void {
    if (self.focused_output) |focused_output| {
        if (focused_output == output) {
            log.err("Attempted to focus on already focused_output. Skipping.", .{});
            return;
        }
    }
    self.focused_output = output;
    log.debug("Focusing on output.", .{});
    // TODO: finish this.

    if (self.server.config.warp_cursor == .@"on-output-change") {
        var layout_box: wlr.Box = undefined;
        self.server.output_layout.wlr_output_layout.getBox(self.focused_output.?.wlr_output, &layout_box);

        if (!layout_box.containsPoint(self.server.wlr_cursor.x, self.server.wlr_cursor.y)) {
            const geometry = output.getGeometry();

            const lx = @intToFloat(f32, layout_box.x + @intCast(i32, geometry.width / 2));
            const ly = @intToFloat(f32, layout_box.y + @intCast(i32, geometry.height / 2));
            if (!self.server.wlr_cursor.warp(null, lx, ly)) {
                log.err("Failed to warp cursor on output change", .{});
            }
        }
    }
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
