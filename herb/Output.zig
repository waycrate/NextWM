// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// herb/output.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();
const Server = @import("Server.zig");

const std = @import("std");
const os = std.os;

const wl = @import("wayland").server.wl;
const zwlr = @import("wayland").server.zwlr;
const wlr = @import("wlroots");

server: *Server,
wlr_output: *wlr.Output,
frame: wl.Listener(*wlr.Output) = wl.Listener(*wlr.Output).init(frame),

// This callback is called everytime an output is ready to display a frame.
pub fn frame(listener: *wl.Listener(*wlr.Output), _: *wlr.Output) void {
    // Get the parent struct, Output.
    const output = @fieldParentPtr(Self, "frame", listener);

    // Get the scene output with respect to the wlr.Output object that's being passed.
    const scene_output = output.server.scene.getSceneOutput(output.wlr_output).?;

    // Commit the output to the scene.
    _ = scene_output.commit();

    // Get current time as the FrameDone event requires it.
    var now: os.timespec = undefined;
    os.clock_gettime(os.CLOCK.MONOTONIC, &now) catch @panic("CLOCK_MONOTONIC not supported");

    // Send the FrameDone event.
    scene_output.sendFrameDone(&now);
}
