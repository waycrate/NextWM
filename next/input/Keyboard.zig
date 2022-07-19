// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/input/Keyboard.zig
//
// Created by:	Aakash Sen Sharma, July 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const allocator = @import("../utils/allocator.zig").allocator;
const log = std.log.scoped(.Keyboard);
const server = &@import("../next.zig").server;
const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const xkb = @import("xkbcommon");

const Server = @import("../Server.zig");
const Cursor = @import("Cursor.zig");

server: *Server,

wlr_input_device: *wlr.InputDevice,
wlr_keyboard: *wlr.Keyboard,

keyboard_key: wl.Listener(*wlr.Keyboard.event.Key) = wl.Listener(*wlr.Keyboard.event.Key).init(keyboardKey),
keyboard_destroy: wl.Listener(*wlr.InputDevice) = wl.Listener(*wlr.InputDevice).init(keyboardDestroy),

pub fn init(self: *Self, device: *wlr.InputDevice) void {
    log.debug("Initializing keyboard device", .{});
    self.* = .{
        .server = server,
        .wlr_input_device = device,
        .wlr_keyboard = device.device.keyboard,
    };
    self.server.keyboards.append(allocator, self) catch {
        log.err("Failed to allocate memory", .{});
        return;
    };

    self.wlr_keyboard.setRepeatInfo(self.server.config.repeat_rate, self.server.config.repeat_delay);

    self.wlr_keyboard.events.key.add(&self.keyboard_key);
    self.wlr_input_device.events.destroy.add(&self.keyboard_destroy);
}

fn keyboardKey(listener: *wl.Listener(*wlr.Keyboard.event.Key), event: *wlr.Keyboard.event.Key) void {
    const self = @fieldParentPtr(Self, "keyboard_key", listener);
    log.debug("Signal: wlr_keyboard_key", .{});

    self.server.input_manager.wlr_idle.notifyActivity(self.server.wlr_seat);

    // Translate libinput keycode -> xkbcommon
    const keycode = event.keycode + 8;
    //const modifiers = self.wlr_keyboard.getModifiers();

    const xkb_state = self.wlr_keyboard.xkb_state orelse return;
    const keysyms = xkb_state.keyGetSyms(keycode);

    for (keysyms) |sym| {
        // Check if the sym is a modifier.
        if (!(@enumToInt(sym) >= xkb.Keysym.Shift_L and @enumToInt(sym) <= xkb.Keysym.Hyper_R)) {
            //TODO: Hide while typing.
        }
    }

    for (keysyms) |sym| {
        if (!(event.state == .released) and handleCompositorBindings(sym)) return;
    }

    self.server.wlr_seat.setKeyboard(self.wlr_input_device);
    self.server.wlr_seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
}

fn handleCompositorBindings(keysym: xkb.Keysym) bool {
    switch (@enumToInt(keysym)) {
        xkb.Keysym.XF86Switch_VT_1...xkb.Keysym.XF86Switch_VT_12 => {
            if (server.wlr_backend.isMulti()) {
                if (server.wlr_backend.getSession()) |session| {
                    session.changeVt(@enumToInt(keysym) - xkb.Keysym.XF86Switch_VT_1 + 1) catch {
                        //TODO: Stop printing, start logging.
                        std.debug.print("Failed to switch VT.", .{});
                    };
                }
            }
            return true;
        },
        else => return false,
    }
}

fn keyboardDestroy(listener: *wl.Listener(*wlr.InputDevice), _: *wlr.InputDevice) void {
    const self = @fieldParentPtr(Self, "keyboard_destroy", listener);
    log.debug("Signal: wlr_input_device_destroy (keyboard)", .{});

    if (std.mem.indexOfScalar(*Self, self.server.keyboards.items, self)) |i| {
        _ = self.server.keyboards.orderedRemove(i);
    }

    self.server.input_manager.setSeatCapabilities();
}
