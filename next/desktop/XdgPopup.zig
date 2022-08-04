// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/desktop/XdgPopup.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const allocator = @import("../utils/allocator.zig").allocator;
const assert = std.debug.assert;
const log = std.log.scoped(.XdgPopup);
const server = &@import("../next.zig").server;
const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Output = @import("Output.zig");
const XdgToplevel = @import("XdgToplevel.zig");
const Server = @import("../Server.zig");
const ParentSurface = union(enum) {
    xdg_toplevel: *XdgToplevel,
    xdg_popup: *Self,
};

wlr_xdg_popup: *wlr.XdgPopup,
parent: ParentSurface,

popups: std.ArrayListUnmanaged(*wlr.XdgPopup) = .{},
server: *Server = server,

output_box: wlr.Box = undefined,

//map: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(handleMap),
//unmap: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(handleUnmap),
//destroy: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(handleDestroy),
//new_popup: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(newPopup),

//commit: wl.Listener(*wlr.Surface) = wl.Listener(*wlr.Surface).init(handleCommit),

pub fn create(xdg_popup: *wlr.XdgPopup, parent: ParentSurface) ?*Self {
    const self: *Self = allocator.create(Self) catch {
        std.log.err("Failed to allocate memory", .{});
        xdg_popup.resource.postNoMemory();
        return null;
    };
    self.* = .{
        .parent = parent,
        .wlr_xdg_popup = xdg_popup,
    };

    if (xdg_popup.base.data == 0) xdg_popup.base.data = @ptrToInt(self);

    switch (parent) {
        .xdg_toplevel => |xdg_toplevel| {
            var box: wlr.Box = undefined;
            xdg_popup.base.getGeometry(&box);

            var lx: f64 = 0;
            var ly: f64 = 0;
            self.server.wlr_output_layout.closestPoint(
                null,
                @intToFloat(f64, xdg_toplevel.geometry.x + box.x),
                @intToFloat(f64, xdg_toplevel.geometry.y + box.y),
                &lx,
                &ly,
            );

            var width: c_int = undefined;
            var height: c_int = undefined;
            if (self.server.wlr_output_layout.outputAt(lx, ly)) |output| {
                output.effectiveResolution(&width, &height);
            } else {
                log.warn("Failed to find output for xdg_popup", .{});
                allocator.destroy(self);
                return null;
            }
            self.output_box = wlr.Box{
                .x = box.x - @floatToInt(c_int, lx),
                .y = box.y - @floatToInt(c_int, ly),
                .width = width,
                .height = height,
            };
        },

        // Nested popup!
        .xdg_popup => |parent_popup| {
            self.output_box = parent_popup.output_box;
        },
    }
    xdg_popup.unconstrainFromBox(&self.output_box);
    return self;
}
