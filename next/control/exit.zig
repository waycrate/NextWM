// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/control/exit.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const server = &@import("../next.zig").server;

const Error = @import("command.zig").Error;

pub fn exitRiver(
    args: []const [:0]const u8,
    _: *?[]const u8,
) !void {
    if (args.len > 1) return Error.TooManyArguments;
    server.wl_server.terminate();
}
