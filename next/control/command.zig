// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/global/command.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const std = @import("std");
const assert = std.debug.assert;

const wlr = @import("wlroots");

pub const Error = error{
    NoCommand,
    NotEnoughArguments,
    OutOfMemory,
    TooManyArguments,
    UnknownCommand,
    UnknownOption,
};

// zig fmt: off
const commands = std.ComptimeStringMap(
    fn ([]const [:0]const u8, *?[]const u8) Error!void,
    .{
        .{ "list-inputs",  @import("inputs.zig").listInputs   },
        .{ "list-outputs", @import("outputs.zig").listOutputs },
        .{ "exit",         @import("exit.zig").exit           },
        .{ "csd",          @import("csd.zig").csdToggle       },
    },
);
// zig fmt: on

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
        Error.NotEnoughArguments => "Not enough arguments provided\n",
        Error.OutOfMemory => "Out of memory\n",
        Error.TooManyArguments => "Too many arguments\n",
        Error.UnknownOption => "Unknown option\n",
        Error.UnknownCommand => "Unknown command\n",
    };
}
