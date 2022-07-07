// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/next.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const allocator = @import("./utils/allocator.zig").allocator;
const build_options = @import("build_options");
const flags = @import("./utils/flags.zig");
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const os = std.os;
const std = @import("std");

// Wl namespace for server-side libwayland bindings.
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Server = @import("Server.zig");

// Server is a public global as we import it in some other files.
pub var server: Server = undefined;

// Tell std.log to leave log_level filtering to us.
pub const log_level: std.log.Level = .debug;
pub var runtime_log_level: std.log.Level = .err;

// Usage text.
const usage: []const u8 =
    \\Usage: next [options]
    \\
    \\  -h, --help                  Print this help message and exit.
    \\  -v, --version               Print the version number and exit.
    \\  -c <command>                Run `sh -c <command>` on startup.
    \\  -d                          Set log level to debug mode.
    \\  -l <level>                  Set the log level:
    \\                                  error, warning, info, or debug.
    \\
;

pub fn main() anyerror!void {
    //NOTE: https://github.com/ziglang/zig/issues/7807
    const argv: [][*:0]const u8 = os.argv;
    const result = flags.parse(argv[1..], &[_]flags.Flag{
        .{ .name = "--help", .kind = .boolean },
        .{ .name = "--version", .kind = .boolean },
        .{ .name = "-c", .kind = .arg },
        .{ .name = "-d", .kind = .boolean },
        .{ .name = "-h", .kind = .boolean },
        .{ .name = "-l", .kind = .arg },
        .{ .name = "-v", .kind = .boolean },
    }) catch {
        try io.getStdErr().writeAll(usage);
        return;
    };

    // Print help message if requested.
    if (result.boolFlag("-h") or result.boolFlag("--help")) {
        try io.getStdOut().writeAll(usage);
        return;
    }

    // Print version information if requested.
    if (result.boolFlag("-v") or result.boolFlag("--version")) {
        try io.getStdOut().writeAll("Next version: " ++ build_options.version ++ "\n");
        return;
    }

    if (result.boolFlag("-d")) {
        runtime_log_level = .debug;
    }

    // Fetch the log level specified or fallback to info.
    if (result.argFlag("-l")) |level| {
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
            try io.getStdErr().writeAll(usage);
            return;
        }
    }

    // Fetching the startup command.
    const startup_command = blk: {
        // If command flag is mentioned, use it.
        if (result.argFlag("-c")) |command| {
            break :blk try allocator.dupeZ(u8, command);
        } else {
            // Try to resolve xdg_config_home or home respectively and use their path's if possible.
            if (os.getenv("XDG_CONFIG_HOME")) |xdg_config_home| {
                break :blk try fs.path.joinZ(allocator, &[_][]const u8{ xdg_config_home, "next/nextrc" });
            } else if (os.getenv("HOME")) |home| {
                break :blk try fs.path.joinZ(allocator, &[_][]const u8{ home, ".config/next/nextrc" });
            } else {
                return;
            }
        }
    };
    defer allocator.free(startup_command);

    // accessZ takes a null terminated strings and checks against the mentioned bit.
    // X_OK is the executable bit.
    os.accessZ(startup_command, os.X_OK) catch |err| {
        if (err == error.PermissionDenied) {
            // R_OK stands for the readable bit
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

    // Initializing wlroots log utility with debug level.
    wlr.log.init(switch (runtime_log_level) {
        .debug => .debug,
        .info => .info,
        .warn, .err => .err,
    });

    // Attempt to initialize the server, deinitialize it once the block ends.
    std.log.info("Initializing server", .{});
    try server.init();
    defer server.deinit();
    try server.start();

    // Fork into a child process.
    var child = try std.ChildProcess.init(&[_][]const u8{ "/bin/sh", "-c", startup_command }, allocator);

    // Deinitialize the child on returning.
    defer child.deinit();

    // Spawn the child.
    try child.spawn();

    // Run the server!
    std.log.info("Running NextWM event loop", .{});
    server.wl_server.run();
}

// Custom logging function.
pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    // If level of the message is higher than the message level specified then don't log it.
    if (@enumToInt(level) > @enumToInt(runtime_log_level)) return;

    // Performing some string formatting and then printing it.
    const level_txt = comptime toUpper(level.asText()) ++ " ";
    const scope_txt = "[" ++ @tagName(scope) ++ "] ";

    const stderr = io.getStdErr().writer();
    stderr.print(scope_txt ++ level_txt ++ format ++ "\n", args) catch {};
}

// Takes a string, uppercases it and returns a sentinel terminated string.
fn toUpper(comptime string: []const u8) *const [string.len:0]u8 {
    comptime {
        var tmp: [string.len:0]u8 = undefined;
        for (tmp) |*char, i| char.* = std.ascii.toUpper(string[i]);
        return &tmp;
    }
}
