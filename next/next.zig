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
const ziglua = @import("ziglua");
const Lua = ziglua.Lua;

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
        \\-c, --config <str>     custom configuration file path.
        \\-d, --debug            set log level to debug mode.
        \\-l, --level <str>      set the log level: error, warnings, or info.
    );

    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{}) catch |err| {
        try stderr.print("Failed to parse arguments: {s}\n", .{@errorName(err)});
        return;
    };
    var args = res.args;
    defer res.deinit();

    // Print help message if requested.
    if (args.help) {
        try stderr.writeAll("Usage: next [options]\n");
        return clap.help(stderr, clap.Help, &params, .{});
    }

    // Print version information if requested.
    if (args.version) {
        try stdout.print("Next version: {s}\n", .{build_options.version});
        return;
    }

    if (args.debug) {
        runtime_log_level = .debug;
    }

    //Fetch the log level specified or fallback to info.
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

    // Fetching the startup command.
    const init_file = blk: {
        // If command flag is mentioned, use it.
        if (args.config) |config| {
            break :blk try allocator.dupeZ(u8, config);
        } else {
            // Try to resolve xdg_config_home or home respectively and use their path's if possible.
            if (os.getenv("XDG_CONFIG_HOME")) |xdg_config_home| {
                break :blk try fs.path.joinZ(allocator, &[_][]const u8{ xdg_config_home, "next/init.lua" });
            } else if (os.getenv("HOME")) |home| {
                break :blk try fs.path.joinZ(allocator, &[_][]const u8{ home, ".config/next/init.lua" });
            } else {
                return;
            }
        }
    };
    defer allocator.free(init_file);

    // Wayland requires XDG_RUNTIME_DIR to be set in order for proper functioning.
    if (os.getenv("XDG_RUNTIME_DIR") == null) {
        std.log.err("XDG_RUNTIME_DIR has not been set.", .{});
        return;
    }

    // Initializing wlroots log utility with debug level.
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

    // Attempt to initialize the server, deinitialize it once the block ends.
    std.log.info("Initializing server", .{});
    try server.init();
    defer server.deinit();
    try server.start();

    try parseConfiguration(init_file);

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
    // If level of the message is higher than the message level specified then don't log it.
    if (@enumToInt(level) > @enumToInt(runtime_log_level)) return;

    // Performing some string formatting and then printing it.
    const level_txt = comptime toUpper(level.asText());
    const scope_txt = "[" ++ @tagName(scope) ++ "] ";

    stderr.print(scope_txt ++ "(" ++ level_txt ++ ") " ++ format ++ "\n", args) catch {};
}

// Takes a string, uppercases it and returns a sentinel terminated string.
fn toUpper(comptime string: []const u8) *const [string.len:0]u8 {
    comptime {
        var tmp: [string.len:0]u8 = undefined;
        for (tmp) |*char, i| char.* = std.ascii.toUpper(string[i]);
        return &tmp;
    }
}

fn parseConfiguration(init_file: [:0]const u8) !void {
    var lua = try Lua.init(allocator);
    defer lua.deinit();

    lua.openBase();

    try lua.doFile(init_file);
}
