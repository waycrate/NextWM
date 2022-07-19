// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/control/border.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const std = @import("std");
const server = &@import("../next.zig").server;
const allocator = @import("../utils/allocator.zig").allocator;

const Error = @import("command.zig").Error;

pub fn setWidth(
    args: []const [:0]const u8,
    out: *?[]const u8,
) !void {
    if (args.len < 2) return Error.NotEnoughArguments;
    if (args.len > 2) return Error.TooManyArguments;

    server.config.border_width = std.fmt.parseInt(u8, args[1], 10) catch {
        out.* = try std.fmt.allocPrint(allocator, "Failed to parse border-width from range 0-255\n", .{});
        return;
    };
}

//TODO: Write a function to iterate over all views and change their border width.
