// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/global/command/inputs.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const std = @import("std");
const server = &@import("../next.zig").server;
const allocator = @import("../utils/allocator.zig").allocator;

const wlr = @import("wlroots");

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
