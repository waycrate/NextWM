// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/desktop/Window.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const allocator = @import("../utils/allocator.zig").allocator;
const log = std.log.scoped(.Window);
const server = &@import("../next.zig").server;
const std = @import("std");

const wlr = @import("wlroots");

const Server = @import("../Server.zig");
const Output = @import("Output.zig");
const XdgToplevel = @import("XdgToplevel.zig");

const Backend = union(enum) {
    xdg_toplevel: XdgToplevel,
};

server: *Server,
output: *Output,

wlr_foreign_toplevel_handle: *wlr.ForeignToplevelHandleV1 = undefined,
backend: Backend,

pub fn init(self: *Self, output: *Output, backend: Backend) !void {
    log.debug("Initializing window", .{});
    // TODO: Set toplevel tags here.
    self.* = .{
        .output = output,
        .backend = backend,
        .wlr_foreign_toplevel_handle = try wlr.ForeignToplevelHandleV1.create(server.wlr_foreign_toplevel_manager),
        .server = server,
    };

    server.pending_windows.append(allocator, self) catch {
        log.err("Failed to allocate memory", .{});
        return;
    };

    switch (self.backend) {
        .xdg_toplevel => |xdg_toplevel| xdg_toplevel.xdg_surface.data = @intFromPtr(self),
    }
}

pub fn getAppId(self: *Self) [*:0]const u8 {
    log.debug("Surface AppID was requested", .{});
    return switch (self.backend) {
        .xdg_toplevel => |xdg_toplevel| xdg_toplevel.getAppId(),
    };
}

pub fn getTitle(self: *Self) [*:0]const u8 {
    log.debug("Surface Title was requested", .{});
    return switch (self.backend) {
        .xdg_toplevel => |xdg_toplevel| xdg_toplevel.getTitle(),
    };
}

pub fn notifyAppId(self: *Self, app_id: [*:0]const u8) void {
    log.debug("AppID data propagated to ftm handle", .{});
    self.wlr_foreign_toplevel_handle.setAppId(app_id);
}

pub fn notifyTitle(self: *Self, title: [*:0]const u8) void {
    log.debug("Title data propagated to ftm handle", .{});
    self.wlr_foreign_toplevel_handle.setTitle(title);
}

pub fn setMon(self: *Self, output: *Output) void {
    if (output == self.output) return;
    switch (self.backend) {
        .xdg_toplevel => |xdg_toplevel| {
            // TODO: Is this performant?
            xdg_toplevel.xdg_surface.surface.sendLeave(self.output.wlr_output);
            xdg_toplevel.xdg_surface.surface.sendEnter(output.wlr_output);
        },
    }
    self.output = output;
}

// Called by backend specific implementation on destroy event.
/// Free window and toplevel on destroy.
pub fn handleDestroy(self: *Self) void {
    switch (self.backend) {
        .xdg_toplevel => |*xdg_toplevel| {
            for (xdg_toplevel.borders) |border| {
                border.node.destroy();
            }
            xdg_toplevel.scene_tree.node.destroy();
        },
    }
    if (std.mem.indexOfScalar(*Self, self.server.mapped_windows.items, self)) |i| {
        log.warn("Window destroyed before unmap event.", .{});
        self.wlr_foreign_toplevel_handle.destroy();

        const window = self.server.mapped_windows.swapRemove(i);
        allocator.destroy(window);
        allocator.destroy(self);
    } else {
        if (std.mem.indexOfScalar(*Self, server.pending_windows.items, self)) |i| {
            self.wlr_foreign_toplevel_handle.destroy();

            const window = self.server.pending_windows.swapRemove(i);
            allocator.destroy(window);
            allocator.destroy(self);
        }
    }

    // Set the focus to the window below the cursor :)
    const window_below_cursor = windowAt(server.wlr_cursor.x, server.wlr_cursor.y) orelse return;
    server.seat.setFocus(window_below_cursor.window, window_below_cursor.surface);
}

const WindowAt = struct {
    window: *Self,
    surface: *wlr.Surface,
    sx: f64,
    sy: f64,
};

pub fn windowAt(
    lx: f64,
    ly: f64,
) ?WindowAt {
    var sx: f64 = undefined;
    var sy: f64 = undefined;

    if (server.wlr_scene.tree.node.at(lx, ly, &sx, &sy)) |node| {
        if (node.type != .buffer) return null;

        const scene_buffer = wlr.SceneBuffer.fromNode(node);
        const scene_surface = wlr.SceneSurface.fromBuffer(scene_buffer) orelse return null;

        var it: ?*wlr.SceneTree = node.parent;
        while (it) |n| : (it = n.node.parent) {
            if (@as(?*Self, @ptrFromInt(n.node.data))) |window| {
                return WindowAt{
                    .window = window,
                    .surface = scene_surface.surface,
                    .sx = sx,
                    .sy = sy,
                };
            }
        }
    }
    return null;
}
