// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// src/input/InputManager.zig
//
// Created by:	Aakash Sen Sharma, July 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const std = @import("std");
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const server = &@import("../next.zig").server;
const Server = @import("../Server.zig");

server: *Server,
wlr_idle: *wlr.Idle,
wlr_input_inhibit_manager: *wlr.InputInhibitManager,
wlr_pointer_constraints: *wlr.PointerConstraintsV1,
wlr_relative_pointer_manager: *wlr.RelativePointerManagerV1,
wlr_virtual_pointer_manager: *wlr.VirtualPointerManagerV1,
wlr_virtual_keyboard_manager: *wlr.VirtualKeyboardManagerV1,

new_input: wl.Listener(*wlr.InputDevice) = wl.Listener(*wlr.InputDevice).init(newInput),
pointer_destroy: wl.Listener(*wlr.InputDevice) = wl.Listener(*wlr.InputDevice).init(pointerDestroy),

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
}

fn newInput(listener: *wl.Listener(*wlr.InputDevice), input_device: *wlr.InputDevice) void {
    const self = @fieldParentPtr(Self, "new_input", listener);

    switch (input_device.type) {
        .keyboard => {
            //TODO: Finish this.
        },
        .pointer => {
            self.server.wlr_cursor.attachInputDevice(input_device);
            input_device.events.destroy.add(&self.pointer_destroy);
        },
        else => {},
    }
}

fn pointerDestroy(listener: *wl.Listener(*wlr.InputDevice), input_device: *wlr.InputDevice) void {
    const self = @fieldParentPtr(Self, "pointer_destroy", listener);
    self.server.wlr_cursor.detachInputDevice(input_device);
}
