// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// src/next.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const flags = @import("flags.zig");
const std = @import("std");
const fs = std.fs;
const io = std.io;
const os = std.os;

const Server = @import("Server.zig");

const wl = @import("wayland").server.wl; // server side zig bindings for libwayland.
const wlr = @import("wlroots");

pub var server: Server = undefined;

const usage: []const u8 =
    \\usage: next [options]
    \\
    \\  -h, --help                  Print this help message and exit.
    \\  -v, --version               Print the version number and exit.
    \\  -l, --log-level <level>     Set the log level.
;

pub fn main() anyerror!void {
    //NOTE: https://github.com/ziglang/zig/issues/7807
    const argv: [][*:0]const u8 = os.argv;
    const result = flags.parse(argv[1..], &[_]flags.Flag{
        .{ .name = "-h", .kind = .boolean },
        .{ .name = "--help", .kind = .boolean },
    }) catch {
        try io.getStdErr().writeAll(usage);
        os.exit(1);
    };

    if (result.boolFlag("-h") or result.boolFlag("--help")) {
        try io.getStdOut().writeAll(usage);
        os.exit(0);
    }

    if (result.args.len != 0) {
        std.log.err("Unknown option '{s}'", .{result.args[0]});
        try io.getStdErr().writeAll(usage);
        os.exit(1);
    }
    // Wayland requires XDG_RUNTIME_DIR to be set in order for proper functioning.
    if (os.getenv("XDG_RUNTIME_DIR") == null) {
        @panic("XDG_RUNTIME_DIR has not been set.");
    }

    // Initializing wlroots log utility with debug level.
    wlr.log.init(.debug);

    // Attempt to initialize the server, deinitialize it once the block ends.
    try server.init();
    defer server.deinit();
    try server.start();

    // Run the server!
    server.wl_server.run();
}
