// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/desktop/XdgPopup.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const allocator = @import("../utils/allocator.zig").allocator;
const log = std.log.scoped(.XdgPopup);
const server = &@import("../next.zig").server;
const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const XdgToplevel = @import("XdgToplevel.zig");
const Server = @import("../Server.zig");
const ParentSurface = union(enum) {
    xdg_toplevel: *XdgToplevel,
    xdg_popup: *Self,
};

wlr_xdg_popup: *wlr.XdgPopup,
parent: ParentSurface,
mapped: bool = false,

popups: std.ArrayListUnmanaged(*Self) = .{},
server: *Server,

output_box: wlr.Box = undefined,

//TODO: Handle SubSurfaces
map: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(handleMap),
unmap: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(handleUnmap),
surface_destroy: wl.Listener(*wlr.XdgSurface) = wl.Listener(*wlr.XdgSurface).init(handleDestroy),
new_popup: wl.Listener(*wlr.XdgPopup) = wl.Listener(*wlr.XdgPopup).init(handleNewPopup),

commit: wl.Listener(*wlr.Surface) = wl.Listener(*wlr.Surface).init(handleCommit),

pub fn create(xdg_popup: *wlr.XdgPopup, parent: ParentSurface) ?*Self {
    const self: *Self = allocator.create(Self) catch {
        std.log.err("Failed to allocate memory", .{});
        xdg_popup.resource.postNoMemory();
        return null;
    };
    self.* = .{
        .parent = parent,
        .wlr_xdg_popup = xdg_popup,
        .server = server,
    };

    if (xdg_popup.base.data == 0) xdg_popup.base.data = @intFromPtr(self);

    switch (parent) {
        .xdg_toplevel => |xdg_toplevel| {
            var box: wlr.Box = undefined;
            xdg_popup.base.getGeometry(&box);

            var lx: f64 = 0;
            var ly: f64 = 0;
            self.server.output_layout.wlr_output_layout.closestPoint(
                null,
                @as(f64, @floatFromInt(xdg_toplevel.geometry.x + box.x)),
                @as(f64, @floatFromInt(xdg_toplevel.geometry.y + box.y)),
                &lx,
                &ly,
            );

            var width: c_int = undefined;
            var height: c_int = undefined;
            if (self.server.output_layout.wlr_output_layout.outputAt(lx, ly)) |output| {
                output.effectiveResolution(&width, &height);
            } else {
                log.warn("Failed to find output for xdg_popup", .{});
                allocator.destroy(self);
                return null;
            }
            self.output_box = wlr.Box{
                .x = box.x - @as(c_int, @intFromFloat(lx)),
                .y = box.y - @as(c_int, @intFromFloat(ly)),
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

pub fn destroy(self: *Self) void {
    self.surface_destroy.link.remove();
    self.map.link.remove();
    self.unmap.link.remove();
    self.new_popup.link.remove();
    self.new_popup.link.remove();

    if (self.mapped) self.commit.link.remove();

    self.destroyPopups();
    allocator.destroy(self);
}

pub fn destroyPopups(self: *Self) void {
    for (self.popups.items) |popup| {
        popup.wlr_xdg_popup.destroy();
        allocator.destroy(popup);
    }
    self.popups.deinit(allocator);
}

fn handleMap(listener: *wl.Listener(*wlr.XdgSurface), _: *wlr.XdgSurface) void {
    const self = @fieldParentPtr(Self, "map", listener);
    log.debug("Signal: wlr_xdg_popup_map", .{});

    self.wlr_xdg_popup.base.surface.events.commit.add(&self.commit);
    self.mapped = true;
}

fn handleCommit(_: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
    log.debug("Signal: wlr_xdg_popup_commit", .{});
}

fn handleUnmap(_: *wl.Listener(*wlr.XdgSurface), _: *wlr.XdgSurface) void {
    log.debug("Signal: wlr_xdg_popup_unmap", .{});
}

fn handleNewPopup(listener: *wl.Listener(*wlr.XdgPopup), wlr_xdg_popup: *wlr.XdgPopup) void {
    const self = @fieldParentPtr(Self, "new_popup", listener);
    log.debug("Signal: wlr_xdg_popup_new_popup", .{});

    if (Self.create(wlr_xdg_popup, self.parent)) |popup| {
        self.popups.append(allocator, popup) catch {
            log.err("Failed to allocate memory", .{});
            return;
        };
    } else {
        log.err("Failed to create new_popup", .{});
    }
}

fn handleDestroy(listener: *wl.Listener(*wlr.XdgSurface), _: *wlr.XdgSurface) void {
    const self = @fieldParentPtr(Self, "surface_destroy", listener);
    log.debug("Signal: wlr_xdg_popup_destroy", .{});

    self.destroy();
}
