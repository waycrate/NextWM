// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/input/InputManager.zig
//
// Created by:	Aakash Sen Sharma, July 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const server = &@import("../next.zig").server;
const allocator = @import("../utils/allocator.zig").allocator;
const log = std.log.scoped(.InputManager);

const Server = @import("../Server.zig");
const Cursor = @import("Cursor.zig");
const Keyboard = @import("Keyboard.zig");

server: *Server,

wlr_idle: *wlr.Idle,
wlr_input_inhibit_manager: *wlr.InputInhibitManager,
wlr_pointer_constraints: *wlr.PointerConstraintsV1,
wlr_relative_pointer_manager: *wlr.RelativePointerManagerV1,
wlr_virtual_pointer_manager: *wlr.VirtualPointerManagerV1,
wlr_virtual_keyboard_manager: *wlr.VirtualKeyboardManagerV1,

new_input: wl.Listener(*wlr.InputDevice) = wl.Listener(*wlr.InputDevice).init(newInput),

request_set_selection: wl.Listener(*wlr.Seat.event.RequestSetSelection) = wl.Listener(*wlr.Seat.event.RequestSetSelection).init(requestSetSelection),
request_set_cursor: wl.Listener(*wlr.Seat.event.RequestSetCursor) = wl.Listener(*wlr.Seat.event.RequestSetCursor).init(requestSetCursor),

pub fn init(self: *Self) !void {
    self.* = .{
        .server = server,
        .wlr_idle = try wlr.Idle.create(server.wl_server),
        .wlr_input_inhibit_manager = try wlr.InputInhibitManager.create(server.wl_server),
        .wlr_pointer_constraints = try wlr.PointerConstraintsV1.create(server.wl_server),
        .wlr_relative_pointer_manager = try wlr.RelativePointerManagerV1.create(server.wl_server),
        .wlr_virtual_pointer_manager = try wlr.VirtualPointerManagerV1.create(server.wl_server),
        .wlr_virtual_keyboard_manager = try wlr.VirtualKeyboardManagerV1.create(server.wl_server),
    };

    server.wlr_backend.events.new_input.add(&self.new_input);
    server.wlr_seat.events.request_set_selection.add(&self.request_set_selection);
    server.wlr_seat.events.request_set_cursor.add(&self.request_set_cursor);
}

fn newInput(listener: *wl.Listener(*wlr.InputDevice), input_device: *wlr.InputDevice) void {
    const self = @fieldParentPtr(Self, "new_input", listener);

    log.debug("Signal: wlr_backend_new_input", .{});

    switch (input_device.type) {
        .keyboard => {
            const keyboard = allocator.create(Keyboard) catch {
                log.debug("Failed to allocate memory", .{});
                return;
            };
            errdefer allocator.destroy(keyboard);

            keyboard.init(input_device);
        },
        .pointer => {
            const pointer = allocator.create(Cursor) catch {
                log.debug("Failed to allocate memory", .{});
                return;
            };
            errdefer allocator.destroy(pointer);

            pointer.init(input_device);
        },
        else => {
            return;
        },
    }

    self.setSeatCapabilities();
}

fn requestSetSelection(listener: *wl.Listener(*wlr.Seat.event.RequestSetSelection), event: *wlr.Seat.event.RequestSetSelection) void {
    const self = @fieldParentPtr(Self, "request_set_selection", listener);
    log.debug("Signal: wlr_seat_request_set_selection", .{});
    self.server.wlr_seat.setSelection(event.source, event.serial);
}

fn requestSetCursor(listener: *wl.Listener(*wlr.Seat.event.RequestSetCursor), event: *wlr.Seat.event.RequestSetCursor) void {
    const self = @fieldParentPtr(Self, "request_set_cursor", listener);
    log.debug("Signal: wlr_seat_request_set_cursor", .{});
    self.server.wlr_cursor.setSurface(event.surface, event.hotspot_x, event.hotspot_y);
}

pub fn setSeatCapabilities(self: *Self) void {
    log.debug("Setting seat capabilities", .{});
    if (self.server.keyboards.items.len > 0) {
        self.server.wlr_seat.setCapabilities(.{
            //TODO: Don't always assume we have a pointer, check this.
            .pointer = true,
            .keyboard = true,
        });
    }
}
