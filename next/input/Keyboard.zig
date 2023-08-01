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

server: *Server,

wlr_input_device: *wlr.InputDevice,
wlr_keyboard: *wlr.Keyboard,

key: wl.Listener(*wlr.Keyboard.event.Key) = wl.Listener(*wlr.Keyboard.event.Key).init(handleKey),
modifiers: wl.Listener(*wlr.Keyboard) = wl.Listener(*wlr.Keyboard).init(handleModifiers),

destroy: wl.Listener(*wlr.InputDevice) = wl.Listener(*wlr.InputDevice).init(handleDestroy),

pub fn init(self: *Self, device: *wlr.InputDevice) !void {
    log.debug("Initializing keyboard device", .{});
    self.* = .{
        .server = server,
        .wlr_input_device = device,
        .wlr_keyboard = device.toKeyboard(),
    };
    self.server.keyboards.append(allocator, self) catch {
        log.err("Failed to allocate memory", .{});
        return;
    };

    const context = xkb.Context.new(.no_flags) orelse return error.XkbContextNewFailed;
    defer context.unref();

    const keymap = xkb.Keymap.newFromNames(context, null, .no_flags) orelse return error.XkbKeymapCreationFailed;
    defer keymap.unref();

    _ = self.wlr_keyboard.setKeymap(keymap);
    self.wlr_keyboard.setRepeatInfo(self.server.config.repeat_rate, self.server.config.repeat_delay);

    self.server.seat.wlr_seat.setKeyboard(self.wlr_keyboard);

    self.wlr_keyboard.events.key.add(&self.key);
    self.wlr_keyboard.events.modifiers.add(&self.modifiers);
    self.wlr_input_device.events.destroy.add(&self.destroy);
}

fn handleKey(listener: *wl.Listener(*wlr.Keyboard.event.Key), event: *wlr.Keyboard.event.Key) void {
    const self = @fieldParentPtr(Self, "key", listener);
    log.debug("Signal: wlr_keyboard_key", .{});

    self.server.input_manager.wlr_idle.notifyActivity(self.server.seat.wlr_seat);

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

    self.server.seat.wlr_seat.setKeyboard(self.wlr_input_device.toKeyboard());
    self.server.seat.wlr_seat.keyboardNotifyKey(event.time_msec, event.keycode, event.state);
}

fn handleModifiers(listener: *wl.Listener(*wlr.Keyboard), _: *wlr.Keyboard) void {
    const self = @fieldParentPtr(Self, "modifiers", listener);
    const wlr_keyboard = self.wlr_input_device.toKeyboard();

    self.server.seat.wlr_seat.setKeyboard(self.wlr_input_device.toKeyboard());
    self.server.seat.wlr_seat.keyboardNotifyModifiers(&wlr_keyboard.modifiers);
}

fn handleDestroy(listener: *wl.Listener(*wlr.InputDevice), _: *wlr.InputDevice) void {
    const self = @fieldParentPtr(Self, "destroy", listener);
    log.debug("Signal: wlr_input_device_destroy (keyboard)", .{});

    if (std.mem.indexOfScalar(*Self, self.server.keyboards.items, self)) |i| {
        const keyboard = self.server.keyboards.swapRemove(i);
        allocator.destroy(keyboard);
    }

    server.input_manager.setSeatCapabilities();
}

fn handleCompositorBindings(keysym: xkb.Keysym) bool {
    switch (@enumToInt(keysym)) {
        xkb.Keysym.XF86Switch_VT_1...xkb.Keysym.XF86Switch_VT_12 => {
            if (server.wlr_backend.isMulti()) {
                if (server.wlr_backend.getSession()) |session| {
                    session.changeVt(@enumToInt(keysym) - xkb.Keysym.XF86Switch_VT_1 + 1) catch {
                        log.err("Failed to switch VT.", .{});
                    };
                }
            }
            return true;
        },
        xkb.Keysym.Escape => {
            server.wl_server.terminate();
            return true;
        },
        xkb.Keysym.Delete => {
            var output: ?[]const u8 = null;
            @import("../control/spawn.zig").spawnCmd(
                &[_][:0]const u8{ "", "alacritty" },
                &output,
            ) catch {};
            if (output) |out| {
                log.err("Spawn command returned: {s}", .{out});
                allocator.free(out);
            }

            return true;
        },
        else => return false,
    }
}
