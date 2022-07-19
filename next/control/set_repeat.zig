// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/control/set_repeat.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const std = @import("std");
const server = &@import("../next.zig").server;
const allocator = @import("../utils/allocator.zig").allocator;

const Error = @import("command.zig").Error;

pub fn setRepeat(
    args: []const [:0]const u8,
    out: *?[]const u8,
) !void {
    if (args.len < 3) return Error.NotEnoughArguments;
    if (args.len > 3) return Error.TooManyArguments;

    const rate = std.fmt.parseInt(i32, args[1], 10) catch {
        out.* = try std.fmt.allocPrint(allocator, "Failed to parse repeat-rate\n", .{});
        return;
    };
    const delay = std.fmt.parseInt(i32, args[2], 10) catch {
        out.* = try std.fmt.allocPrint(allocator, "Failed to parse repeat-delay\n", .{});
        return;
    };

    server.config.repeat_rate = rate;
    server.config.repeat_delay = delay;

    for (server.keyboards.items) |keyboard| {
        keyboard.wlr_input_device.device.keyboard.setRepeatInfo(rate, delay);
    }
}
