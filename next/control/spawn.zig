// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/control/spawn.zig
//
// Created by:	Aakash Sen Sharma, July 2023
// Copyright:	(C) 2023, Aakash Sen Sharma & Contributors

const std = @import("std");
const os = std.os;
const allocator = @import("../utils/allocator.zig").allocator;
const log = std.log.scoped(.SpawnControl);
const c = @import("../utils/c.zig");

const Error = @import("command.zig").Error;

pub fn spawnCmd(
    args: []const [:0]const u8,
    out: *?[]const u8,
) Error!void {
    if (args.len < 2) return Error.NotEnoughArguments;
    if (args.len > 2) return Error.TooManyArguments;

    log.debug("Attempting to run shell command: {s}", .{args[1]});

    const cmd = [_:null]?[*:0]const u8{ "/bin/sh", "-c", args[1], null };
    const pid = os.fork() catch |err| {
        log.err("Fork failed: {s}", .{@errorName(err)});

        out.* = try std.fmt.allocPrint(allocator, "fork failed!", .{});
        return Error.OSError;
    };

    if (pid == 0) {
        if (c.setsid() < 0) unreachable;
        if (os.system.sigprocmask(os.SIG.SETMASK, &os.empty_sigset, null) < 0) unreachable;
        const sig_dfl = os.Sigaction{
            .handler = .{ .handler = os.SIG.DFL },
            .mask = os.empty_sigset,
            .flags = 0,
        };
        os.sigaction(os.SIG.PIPE, &sig_dfl, null) catch |err| {
            log.err("Sigaction failed: {s}", .{@errorName(err)});
            return Error.OSError;
        };

        const pid2 = os.fork() catch c._exit(1);
        if (pid2 == 0) os.execveZ("/bin/sh", &cmd, std.c.environ) catch c._exit(1);

        c._exit(0);
    }

    const exit_code = os.waitpid(pid, 0);
    if (!os.W.IFEXITED(exit_code.status) or
        (os.W.IFEXITED(exit_code.status) and os.W.EXITSTATUS(exit_code.status) != 0))
    {
        out.* = try std.fmt.allocPrint(allocator, "Fork failed", .{});
        return Error.OSError;
    }
}
