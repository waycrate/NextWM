// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/desktop/OutputLayout.zig
//
// Created by:	Aakash Sen Sharma, January 2023
// Copyright:	(C) 2023, Aakash Sen Sharma & Contributors

const Self = @This();

const log = std.log.scoped(.OutputLayout);
const server = &@import("../next.zig").server;
const Server = @import("../Server.zig");
const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

server: *Server,

wlr_output_layout: *wlr.OutputLayout,

layout_change: wl.Listener(*wlr.OutputLayout) = wl.Listener(*wlr.OutputLayout).init(layoutChange),

pub fn init(self: *Self) !void {
    self.* = .{
        .server = server,
        .wlr_output_layout = try wlr.OutputLayout.create(),
    };

    self.wlr_output_layout.events.change.add(&self.layout_change);
}

pub fn deinit(self: *Self) void {
    self.wlr_output_layout.destroy();
}

fn layoutChange(listener: *wl.Listener(*wlr.OutputLayout), _: *wlr.OutputLayout) void {
    const self = @fieldParentPtr(Self, "layout_change", listener);
    log.debug("Signal: wlr_output_layout_layout_change", .{});

    // Everytime an output is resized / added / removed, we redo wallpaper rendering.
    // This is probably not efficient but without it in nested sessions, if wlr_output is resized, the wallpaper doesn't get resized accordingly.
    for (self.server.outputs.items) |output| {
        if (self.server.seat.focused_output) |_| {} else {
            self.server.seat.focusOutput(output);
        }

        if (output.has_wallpaper) {
            output.init_wallpaper_rendering() catch |err| {
                log.err("Error occured: {s}", .{@errorName(err)});
                log.err("Skipping wallpaper setting.", .{});
            };
        }
    }

    //TODO: Finish this!
    //TODO: Take windows from deactivated monitors and rearrange them.
    //TODO: When a monitor mode changes, reorient it's child windows.
    //TODO: Handle layout changes.
}
