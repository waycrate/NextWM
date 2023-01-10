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

fn layoutChange(_: *wl.Listener(*wlr.OutputLayout), _: *wlr.OutputLayout) void {
    log.debug("Signal: wlr_output_layout_layout_change", .{});

    //TODO: Finish this!
    //TODO: Take windows from deactivated monitors and rearrange them.
    //TODO: When a monitor mode changes, reorient it's child windows.
    //TODO: Handle layout changes.
}
