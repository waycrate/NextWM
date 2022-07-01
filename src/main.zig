// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// src/main.zig
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

// Instantiating the server.
pub var server: Server = undefined;

pub fn main() anyerror!void {
    // Wayland requires XDG_RUNTIME_DIR to be set in order for proper functioning.
    if (os.getenv("XDG_RUNTIME_DIR") == null) {
        @panic("XDG_RUNTIME_DIR has not been set.");
    }

    // Initializing wlroots log utility with debug level.
    wlr.log.init(.debug);

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
