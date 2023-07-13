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

axis: wl.Listener(*wlr.Pointer.event.Axis) = wl.Listener(*wlr.Pointer.event.Axis).init(handleAxis),
button: wl.Listener(*wlr.Pointer.event.Button) = wl.Listener(*wlr.Pointer.event.Button).init(handleButton),
frame: wl.Listener(*wlr.Cursor) = wl.Listener(*wlr.Cursor).init(handleFrame),
motion: wl.Listener(*wlr.Pointer.event.Motion) = wl.Listener(*wlr.Pointer.event.Motion).init(handleMotion),
motion_absolute: wl.Listener(*wlr.Pointer.event.MotionAbsolute) = wl.Listener(*wlr.Pointer.event.MotionAbsolute).init(handleMotionAbsolute),

pointer_destroy: wl.Listener(*wlr.InputDevice) = wl.Listener(*wlr.InputDevice).init(pointerDestroy),

pub fn init(self: *Self, device: *wlr.InputDevice) void {
    log.debug("Initializing pointer device", .{});

    self.* = .{
        .server = server,
        .wlr_input_device = device,
    };

    // These listeners only need to be registered once against the wlr_cursor.
    if (self.server.cursors.items.len == 0) {
        self.server.wlr_cursor.events.axis.add(&self.axis);
        self.server.wlr_cursor.events.button.add(&self.button);
        self.server.wlr_cursor.events.frame.add(&self.frame);
        self.server.wlr_cursor.events.motion.add(&self.motion);
        self.server.wlr_cursor.events.motion_absolute.add(&self.motion_absolute);
    }

    self.server.cursors.append(allocator, self) catch {
        log.err("Failed to allocate memory", .{});
        return;
    };
    //TODO: We should modify the pointer libinput object here to support features such as tap to click.

    self.server.wlr_cursor.attachInputDevice(self.wlr_input_device);

    self.wlr_input_device.events.destroy.add(&self.pointer_destroy);
}

fn pointerDestroy(listener: *wl.Listener(*wlr.InputDevice), input_device: *wlr.InputDevice) void {
    const self = @fieldParentPtr(Self, "pointer_destroy", listener);
    log.debug("Signal: wlr_input_device_destroy (pointer)", .{});

    if (std.mem.indexOfScalar(*Self, self.server.cursors.items, self)) |i| {
        const cursor = self.server.cursors.swapRemove(i);
        allocator.destroy(cursor);
    }

    server.input_manager.setSeatCapabilities();
    server.wlr_cursor.detachInputDevice(input_device);
}

// NOTE: Do we need anything else here?
pub fn handleAxis(listener: *wl.Listener(*wlr.Pointer.event.Axis), event: *wlr.Pointer.event.Axis) void {
    const self = @fieldParentPtr(Self, "axis", listener);
    log.debug("Signal: wlr_pointer_axis", .{});

    self.server.seat.wlr_seat.pointerNotifyAxis(
        event.time_msec,
        event.orientation,
        event.delta,
        event.delta_discrete,
        event.source,
    );
}

// TODO: Handle custom button bindings.
pub fn handleButton(listener: *wl.Listener(*wlr.Pointer.event.Button), event: *wlr.Pointer.event.Button) void {
    const self = @fieldParentPtr(Self, "button", listener);
    log.debug("Signal: wlr_pointer_button", .{});

    _ = self.server.seat.wlr_seat.pointerNotifyButton(event.time_msec, event.button, event.state);
}

pub fn handleFrame(listener: *wl.Listener(*wlr.Cursor), _: *wlr.Cursor) void {
    const self = @fieldParentPtr(Self, "frame", listener);
    log.debug("Signal: wlr_cursor_frame", .{});
    self.server.seat.wlr_seat.pointerNotifyFrame();
}

//TODO: Finish these!
pub fn handleMotion(_: *wl.Listener(*wlr.Pointer.event.Motion), _: *wlr.Pointer.event.Motion) void {
    log.debug("Signal: wlr_cursor_motion", .{});
}

pub fn handleMotionAbsolute(_: *wl.Listener(*wlr.Pointer.event.MotionAbsolute), _: *wlr.Pointer.event.MotionAbsolute) void {
    log.debug("Signal: wlr_cursor_motion_absolute", .{});
}
