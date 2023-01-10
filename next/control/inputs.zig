// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/control/inputs.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const std = @import("std");
const server = &@import("../next.zig").server;
const allocator = @import("../utils/allocator.zig").allocator;

const Error = @import("command.zig").Error;

pub fn listInputs(
    args: []const [:0]const u8,
    out: *?[]const u8,
) !void {
    if (args.len > 1) return Error.TooManyArguments;

    var output = std.ArrayList(u8).init(allocator);
    const writer = output.writer();

    for (server.keyboards.items) |device| {
        try writer.print("Keyboard: {s}\n", .{
            device.wlr_input_device.name,
        });
    }
    for (server.cursors.items) |device| {
        try writer.print("Pointer: {s}\n", .{
            device.wlr_input_device.name,
        });
    }
    out.* = output.toOwnedSlice();
}

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
        keyboard.wlr_input_device.toKeyboard().setRepeatInfo(rate, delay);
    }
}
