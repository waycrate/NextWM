// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/next.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const allocator = @import("utils/allocator.zig").allocator;
const build_options = @import("build_options");
const c = @import("utils/c.zig");
const clap = @import("clap");
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const os = std.os;
const std = @import("std");

const wlr = @import("wlroots");

const Server = @import("Server.zig");
const stderr = io.getStdErr().writer();
const stdout = io.getStdOut().writer();

// Server is a public global as we import it in some other files.
pub var server: Server = undefined;

// Tell std.log to leave log_level filtering to us.
pub const log_level: std.log.Level = .debug;
pub var runtime_log_level: std.log.Level = .err;

pub fn main() anyerror!void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             print this help message and exit.
        \\-v, --version          print the version number and exit.
        \\-c, --command <str>    run `sh -c <str>` on startup.
        \\-d, --debug            set log level to debug mode.
        \\-l, --level <str>      set the log level: error, warnings, or info.
    );

    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{}) catch |err| {
        try stderr.print("Failed to parse arguments: {s}\n", .{@errorName(err)});
        return;
    };
    var args = res.args;
    defer res.deinit();

    if (args.help != 0) {
        try stderr.writeAll("Usage: next [options]\n");
        return clap.help(stderr, clap.Help, &params, .{});
    }

    if (args.version != 0) {
        try stdout.print("Next version: {s}\n", .{build_options.version});
        return;
    }

    if (args.debug != 0) {
        runtime_log_level = .debug;
    }

    if (args.level) |level| {
        if (mem.eql(u8, level, std.log.Level.err.asText())) {
            runtime_log_level = .err;
        } else if (mem.eql(u8, level, std.log.Level.warn.asText())) {
            runtime_log_level = .warn;
        } else if (mem.eql(u8, level, std.log.Level.info.asText())) {
            runtime_log_level = .info;
        } else if (mem.eql(u8, level, std.log.Level.debug.asText())) {
            runtime_log_level = .debug;
        } else {
            std.log.err("Invalid log level '{s}'", .{level});
            return;
        }
    }

    const startup_command = blk: {
        if (args.command) |command| {
            break :blk try allocator.dupeZ(u8, command);
        } else {
            if (os.getenv("XDG_CONFIG_HOME")) |xdg_config_home| {
                break :blk try fs.path.joinZ(allocator, &.{ xdg_config_home, "next/nextrc" });
            } else if (os.getenv("HOME")) |home| {
                break :blk try fs.path.joinZ(allocator, &.{ home, ".config/next/nextrc" });
            } else {
                return;
            }
        }
    };
    defer allocator.free(startup_command);

    // X_OK -> executable bit.
    os.accessZ(startup_command, os.X_OK) catch |err| {
        if (err == error.PermissionDenied) {
            // R_OK -> readable bit
            if (os.accessZ(startup_command, os.R_OK)) {
                // If the file is readable but cannot be executed then it must not have the execution bit set.
                std.log.err("Failed to run nextrc file: {s}\nPlease mark the file executable with the following command:\n    chmod +x {s}", .{ startup_command, startup_command });
                return;
            } else |_| {}
            std.log.err("Failed to run nextrc file: {s}\n{s}", .{ startup_command, @errorName(err) });
            return;
        }
    };

    // Wayland requires XDG_RUNTIME_DIR to be set in order for proper functioning.
    if (os.getenv("XDG_RUNTIME_DIR") == null) {
        std.log.err("XDG_RUNTIME_DIR has not been set.", .{});
        return;
    }

    // TODO: Remove this entirely when zig gets good var-arg support.
    wlr_fmt_log(switch (runtime_log_level) {
        .debug => .debug,
        .info => .info,
        .warn, .err => .err,
    });

    // Ignore SIGPIPE so the compositor doesn't get killed when attempting to write to a read-end-closed socket.
    // TODO: Remove this handler entirely: https://github.com/ziglang/zig/pull/11982
    const sig_ign = os.Sigaction{
        .handler = .{ .handler = os.SIG.IGN },
        .mask = os.empty_sigset,
        .flags = 0,
    };
    try os.sigaction(os.SIG.PIPE, &sig_ign, null);

    std.log.scoped(.Next).info("Initializing server", .{});
    try server.init();
    defer server.deinit();

    try server.start();

    const pid = try os.fork();
    if (pid == 0) {
        var errno = os.errno(c.setsid());
        if (@intFromEnum(errno) != 0) {
            std.log.err("Setsid syscall failed: {any}", .{errno});
        }

        // SET_MASK sets the blocked signal to an empty signal set in this case.
        errno = os.errno(os.system.sigprocmask(os.SIG.SETMASK, &os.empty_sigset, null));
        if (@intFromEnum(errno) != 0) {
            std.log.err("Sigprocmask syscall failed: {any}", .{errno});
        }

        // Setting default handler for sigpipe.
        const sig_dfl = os.Sigaction{
            .handler = .{ .handler = os.SIG.DFL },
            .mask = os.empty_sigset,
            .flags = 0,
        };
        try os.sigaction(os.SIG.PIPE, &sig_dfl, null);

        // NOTE: it's convention for the first element in the argument vector to be same as the invoking binary.
        // Read https://man7.org/linux/man-pages/man2/execve.2.html for more info.
        const c_argv = [_:null]?[*:0]const u8{ "/bin/sh", "-c", startup_command, null };
        os.execveZ("/bin/sh", &c_argv, std.c.environ) catch os.exit(1);
    }

    // Sending sigterm to a negative pid traverses down it's child list and sends sigterm to each of them.
    // Read https://man7.org/linux/man-pages/man2/kill.2.html for more info.
    defer os.kill(-pid, os.SIG.TERM) catch |err| {
        std.log.err("Failed to kill init-child: {d} {s}", .{ pid, @errorName(err) });
    };

    // Run the server!
    std.log.info("Running NextWM event loop", .{});
    server.wl_server.run();
}

extern fn wlr_fmt_log(importance: wlr.log.Importance) void;
export fn wlr_log_callback(importance: wlr.log.Importance, ptr: [*:0]const u8, len: usize) void {
    switch (importance) {
        .err => log(.err, .Wlroots, "{s}", .{ptr[0..len]}),
        .info => log(.info, .Wlroots, "{s}", .{ptr[0..len]}),
        .debug => log(.debug, .Wlroots, "{s}", .{ptr[0..len]}),
        .silent, .last => unreachable,
    }
}

// Custom logging function.
pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@intFromEnum(level) > @intFromEnum(runtime_log_level)) return;

    const level_txt = comptime toUpper(level.asText());
    const scope_txt = "[" ++ @tagName(scope) ++ "] ";

    stderr.print(scope_txt ++ "(" ++ level_txt ++ ") " ++ format ++ "\n", args) catch {};
}

fn toUpper(comptime string: []const u8) *const [string.len:0]u8 {
    comptime {
        var tmp: [string.len:0]u8 = undefined;
        for (&tmp, 0..) |*char, i| char.* = std.ascii.toUpper(string[i]);
        return &tmp;
    }
}
