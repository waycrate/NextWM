// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/global/command.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const std = @import("std");
const wlr = @import("wlroots");
const assert = std.debug.assert;

pub const Error = error{
    NoCommand,
    OutOfMemory,
    TooManyArguments,
    UnknownCommand,
};

const commands = std.ComptimeStringMap(
    fn ([]const [:0]const u8, *?[]const u8) Error!void,
    .{
        .{ "list-inputs", @import("inputs.zig").listInputs },
    },
);

pub fn run(
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    assert(out.* == null);
    if (args.len == 0) return Error.NoCommand;
    const func = commands.get(args[0]) orelse return Error.UnknownCommand;
    try func(args, out);
}

pub fn errToMsg(err: Error) [:0]const u8 {
    return switch (err) {
        Error.NoCommand => "No command provided\n",
        Error.OutOfMemory => "Out of memory\n",
        Error.TooManyArguments => "Too many arguments\n",
        Error.UnknownCommand => "Unknown command\n",
    };
}
