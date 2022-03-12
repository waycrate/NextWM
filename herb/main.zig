// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// herb/main.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const std = @import("std");
const fs = std.fs;
const gpa = std.heap.c_allocator; // zig has no default memory allocator unlike c (malloc, realloc, free) , so we use c_allocator while linking against libc.
const os = std.os;

const Server = @import("Server.zig");

const wl = @import("wayland").server.wl; // server side zig bindings for libwayland.
const wlr = @import("wlroots"); // zig bindings for wlroots.

pub fn main() anyerror!void {
    // Note: os.getenv returns an optional []const u8 ( string ) so we can simply check against null.
    if (os.getenv("XDG_RUNTIME_DIR") == null) {
        @panic("XDG_RUNTIME_DIR has not been set.");
    }

    /////////////////////////////// This will be used eventually.
    // We assign the block an identifier - "config".
    const config_path = config: {
        // This notation attempts to access the optional []const u8 ( string ) if it is not null, else it jumps to else if and else cases subsequently.
        if (os.getenv("XDG_CONFIG_HOME")) |xdg_config_home| {
            // If we did get a string return, break back into the config scope and attempt to create a path to the config file.
            break :config try fs.path.joinZ(gpa, &[_][]const u8{ xdg_config_home, "herbwm/herbwmrc" });
        } else if (os.getenv("HOME")) |home| {
            // If we didn't get a string return from os.getenv("XDG..."), then check for $HOME and if we get a path then attempt to resolve it.
            break :config try fs.path.joinZ(gpa, &[_][]const u8{ home, ".config/herbwm/herbwmrc" });
        } else {
            // If we didn't get any matches, panic.
            @panic("Failed to read $XDG_CONFIG_HOME and $HOME environment variables. Unable to resolve config file path.");
        }
    };
    gpa.free(config_path); // You have to free all joinZ calls.
    ///////////////////////////////

    // Initializing wlroots log utility with debug level.
    wlr.log.init(.debug);

    // Instantiating the server.
    var server: Server = undefined;

    // Attempt to initialize the server, if it fails then de-initialize it.
    try server.init();
    defer server.deinit();
    try server.start();

    // Checking if a program to run was passed as the second argument to the compositor and then running it as a child process.
    if (os.argv.len >= 2) {

        // Get the command passed on after the binary name.
        const cmd = std.mem.span(os.argv[1]);

        // Fork into a child process.
        var child = try std.ChildProcess.init(&[_][]const u8{ "/bin/sh", "-c", cmd }, gpa);

        // Deinitialize the child on returning.
        defer child.deinit();

        // Spawn the child.
        try child.spawn();
    }

    // Run the server!
    server.wl_server.run();
}
