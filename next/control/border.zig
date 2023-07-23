// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/control/border.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const std = @import("std");
const server = &@import("../next.zig").server;
const allocator = @import("../utils/allocator.zig").allocator;

const wlr = @import("wlroots");

const Error = @import("command.zig").Error;

pub fn setWidth(
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    if (args.len < 2) return Error.NotEnoughArguments;
    if (args.len > 2) return Error.TooManyArguments;

    server.config.border_width = std.fmt.parseInt(u8, args[1], 10) catch {
        out.* = try std.fmt.allocPrint(allocator, "Failed to parse border-width from range 0-255\n", .{});
        return;
    };

    for (server.mapped_windows.items) |window| {
        switch (window.backend) {
            .xdg_toplevel => |*xdg_toplevel| {
                var geom: wlr.Box = undefined;
                xdg_toplevel.xdg_surface.getGeometry(&geom);
                _ = xdg_toplevel.resize(geom.x, geom.y, geom.width, geom.height);
            },
        }
    }
}

pub fn setColor(
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    if (args.len < 2) return Error.NotEnoughArguments;
    if (args.len > 2) return Error.TooManyArguments;

    server.config.border_color = parseRgba(args[1]) catch |err| {
        out.* = try std.fmt.allocPrint(allocator, "Failed to parse border-color: {s}\n", .{@errorName(err)});
        return;
    };

    for (server.mapped_windows.items) |window| {
        switch (window.backend) {
            .xdg_toplevel => |xdg_toplevel| {
                for (xdg_toplevel.borders) |border| {
                    border.setColor(&server.config.border_color);
                }
            },
        }
    }
}

pub fn parseRgba(_: []const u8) ![4]f32 {
    //TODO: Finish this eventually.
    return [_]f32{ 1, 0, 0, 1 };
}
