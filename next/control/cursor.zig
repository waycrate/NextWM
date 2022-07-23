// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/control/cursor.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const std = @import("std");
const server = &@import("../next.zig").server;
const allocator = @import("../utils/allocator.zig").allocator;

const Error = @import("command.zig").Error;
const CursorWarpMode = @import("../Config.zig").CursorWarpMode;

pub fn hideCursor(
    args: []const [:0]const u8,
    out: *?[]const u8,
) !void {
    if (args.len > 3) return Error.TooManyArguments;
    if (args.len < 3) return Error.NotEnoughArguments;

    if (std.mem.eql(u8, "when-typing", args[1])) {
        if (std.mem.eql(u8, "true", args[2])) {
            server.config.cursor_hide_when_typing = true;
        } else if (std.mem.eql(u8, "false", args[2])) {
            server.config.cursor_hide_when_typing = false;
        } else {
            out.* = try std.fmt.allocPrint(allocator, "Invalid cursor state provided.", .{});
        }
    } else {
        return Error.UnknownOption;
    }
    server.input_manager.hideCursor();
}

pub fn warpCursor(
    args: []const [:0]const u8,
    out: *?[]const u8,
) !void {
    if (args.len > 2) return Error.TooManyArguments;
    if (args.len < 2) return Error.NotEnoughArguments;

    const state = std.meta.stringToEnum(CursorWarpMode, args[1]);
    if (state) |s| {
        server.config.warp_cursor = s;
        return;
    } else {
        out.* = try std.fmt.allocPrint(allocator, "Failed to parse provided state.\n", .{});
    }
}
