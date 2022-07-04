// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/next.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const flags = @import("./utils/flags.zig");
const allocator = @import("./utils/allocator.zig").allocator;
const std = @import("std");
const io = std.io;
const os = std.os;
const fs = std.fs;
const mem = std.mem;
const log = std.log.scoped(.next);

const Server = @import("Server.zig");

// Wl namespace for server-side libwayland bindings.
const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

// Server is a public global as we import it in some other files.
pub var server: Server = undefined;

// Usage text.
const usage: []const u8 =
    \\usage: next [options]
    \\
    \\  -h, --help                  Print this help message and exit.
    \\  -c <command>                Run `sh -c <command>` on startup.
    \\  -l <level>                  Set the log level:
    \\                                  error, warning, info, or debug
    \\
;

pub fn main() anyerror!void {
    //NOTE: https://github.com/ziglang/zig/issues/7807
    const argv: [][*:0]const u8 = os.argv;
    const result = flags.parse(argv[1..], &[_]flags.Flag{
        .{ .name = "-h", .kind = .boolean },
        .{ .name = "--help", .kind = .boolean },
        .{ .name = "-l", .kind = .arg },
        .{ .name = "-c", .kind = .arg },
    }) catch {
        try io.getStdErr().writeAll(usage);
        os.exit(1);
    };

    // Print help message if requested.
    if (result.boolFlag("-h") or result.boolFlag("--help")) {
        try io.getStdOut().writeAll(usage);
        return;
    }

    // Fetch the log level specified or fallback to err.
    var log_level: std.log.Level = .err;
    if (result.argFlag("-l")) |level| {
        if (mem.eql(u8, level, std.log.Level.err.asText())) {
            log_level = .err;
        } else if (mem.eql(u8, level, std.log.Level.warn.asText())) {
            log_level = .warn;
        } else if (mem.eql(u8, level, std.log.Level.info.asText())) {
            log_level = .info;
        } else if (mem.eql(u8, level, std.log.Level.debug.asText())) {
            log_level = .debug;
        } else {
            log.err("Invalid log level '{s}'", .{level});
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
                log.err("Failed to run nextrc file: {s}\nPlease mark the file executable with the following command:\n    chmod +x {s}", .{ startup_command, startup_command });
                return;
            } else |_| {}
            log.err("Failed to run nextrc file: {s}\n{s}", .{ startup_command, @errorName(err) });
            return;
        }
    };

    // Wayland requires XDG_RUNTIME_DIR to be set in order for proper functioning.
    if (os.getenv("XDG_RUNTIME_DIR") == null) {
        @panic("XDG_RUNTIME_DIR has not been set.");
    }

    // Initializing wlroots log utility with debug level.
    wlr.log.init(switch (log_level) {
        .debug => .debug,
        .info => .info,
        .warn, .err => .err,
    });

    // Attempt to initialize the server, deinitialize it once the block ends.
    log.info("Initializing server", .{});
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
    server.wl_server.run();
}
