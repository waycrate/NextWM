// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/input/Cursor.zig
//
// Created by:	Aakash Sen Sharma, July 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const std = @import("std");
const Server = @import("../Server.zig");
const allocator = @import("../utils/allocator.zig").allocator;
const server = &@import("../next.zig").server;
const log = std.log.scoped(.Cursor);

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

server: *Server,

wlr_input_device: *wlr.InputDevice,
pointer_destroy: wl.Listener(*wlr.InputDevice) = wl.Listener(*wlr.InputDevice).init(pointerDestroy),

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
}

fn pointerDestroy(listener: *wl.Listener(*wlr.InputDevice), input_device: *wlr.InputDevice) void {
    const self = @fieldParentPtr(Self, "pointer_destroy", listener);
    log.debug("Signal: wlr_input_device_destroy (pointer)", .{});
    self.server.wlr_cursor.detachInputDevice(input_device);
}
