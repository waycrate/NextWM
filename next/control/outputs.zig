// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/control/outputs.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const std = @import("std");
const server = &@import("../next.zig").server;
const allocator = @import("../utils/allocator.zig").allocator;

const Error = @import("command.zig").Error;

pub fn listOutputs(
    args: []const [:0]const u8,
    out: *?[]const u8,
) !void {
    if (args.len > 1) return Error.TooManyArguments;

    var data = std.ArrayList(u8).init(allocator);
    const writer = data.writer();

    for (server.outputs.items) |output| {
        const geometry = output.getGeometry();
        try writer.print("{s}\n\tx: {d} y: {d} width: {d} height: {d}\n", .{
            output.wlr_output.name,
            geometry.x,
            geometry.y,
            geometry.width,
            geometry.height,
        });
    }
    out.* = data.toOwnedSlice();
}
