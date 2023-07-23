// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/control/command.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const std = @import("std");
const assert = std.debug.assert;

const border = @import("border.zig");
const csd = @import("csd.zig");
const cursor = @import("cursor.zig");
const exit = @import("exit.zig");
const inputs = @import("inputs.zig");
const outputs = @import("outputs.zig");
const spawn = @import("spawn.zig");

pub const Error = error{
    NoCommand,
    NotEnoughArguments,
    OutOfMemory,
    TooManyArguments,
    UnknownCommand,
    UnknownOption,
    OSError,
};

// zig fmt: off
const commands = std.ComptimeStringMap(
    *const fn ([]const [:0]const u8, *?[]const u8) Error!void,
    .{
        .{ "spawn",                         spawn.spawnCmd           },
        .{ "wallpaper",                     outputs.setWallpaper     },
        //TODO: We should change *-* style commands to subcommand based systems. Eg: `border width set 3` / `border color set focused ...`
        .{ "border-width",                  border.setWidth          },
        // TODO: This is just a catch all. We will create border-focused, border-unfocused, etc soon.
        .{ "border-color",                  border.setColor          },
        .{ "csd",                           csd.csdToggle            },
        .{ "exit",                          exit.exitRiver           },
        //TODO: We should change *-* style commands to subcommand based systems. Eg: `list inputs` / `list outputs`
        .{ "list-inputs",                   inputs.listInputs        },
        .{ "list-outputs",                  outputs.listOutputs      },
        .{ "set-repeat-rate",               inputs.setRepeat         },
        .{ "warp-cursor",                   cursor.warpCursor        },
        .{ "hide-cursor",                   cursor.hideCursor        },
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
        Error.OSError => "OS error\n",
    };
}
