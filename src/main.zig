// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// src/main.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const std = @import("std");
const fs = std.fs;
const os = std.os;

const Server = @import("Server.zig");

const wl = @import("wayland").server.wl; // server side zig bindings for libwayland.
const wlr = @import("wlroots");

pub var server: Server = undefined;

pub fn main() anyerror!void {
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
