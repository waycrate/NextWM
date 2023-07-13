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
        //TODO: See what is dpmsStatus
        //TODO: Add model, serial, scale, transform, focused_status, vrr, refresh rate
        try writer.print("{s}\n\t{d}x{d} at {d},{d}\n\tScale: {d}\n\tDescription: {s}\n\tMake: {s}\n\tEnabled: {d}\n\tVRR: {d}\n", .{
            output.wlr_output.name,
            geometry.width,
            geometry.height,
            geometry.x,
            geometry.y,
            output.wlr_output.scale,
            output.getDescription(),
            output.getMake(),
            @boolToInt(output.wlr_output.enabled),
            @boolToInt(output.wlr_output.adaptive_sync_status == .enabled),
        });
    }
    out.* = data.toOwnedSlice();
}
