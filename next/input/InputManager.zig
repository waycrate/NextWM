// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/input/InputManager.zig
//
// Created by:	Aakash Sen Sharma, July 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const allocator = @import("../utils/allocator.zig").allocator;
const log = std.log.scoped(.InputManager);
const server = &@import("../next.zig").server;
const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

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

    self.server.wlr_backend.events.new_input.add(&self.new_input);
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

            keyboard.init(input_device) catch |err| {
                log.err("Failed to initialize keyboard device: {s}", .{@errorName(err)});
                allocator.destroy(keyboard);
                return;
            };
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

/// Make sure to use this function after making all changes to &server.cursors and &server.keyboards array-lists.
pub fn setSeatCapabilities(self: *Self) void {
    const has_keyboard = (self.server.keyboards.items.len > 0);
    const has_pointer = (self.server.cursors.items.len > 0);

    log.debug("Setting seat capabilities: Pointer->{} Keyboard->{}", .{ has_pointer, has_keyboard });
    self.server.seat.wlr_seat.setCapabilities(.{
        .pointer = has_pointer,
        .keyboard = has_keyboard,
    });
}

pub fn hideCursor(self: *Self) void {
    //TODO: Check if any buttons are currently pressed then don't hide the cursor.
    // if (self.pressed_count > 0) return;
    // self.hidden = true;
    //TODO: Check rivers implementation.
    self.server.wlr_cursor.setImage(null, 0, 0, 0, 0, 0, 0);
    self.server.seat.wlr_seat.pointerNotifyClearFocus();
}
