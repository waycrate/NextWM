// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/desktop/Output.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const allocator = @import("../utils/allocator.zig").allocator;
const log = std.log.scoped(.Output);
const os = std.os;
const server = &@import("../next.zig").server;
const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Server = @import("../Server.zig");

server: *Server,

wlr_output: *wlr.Output,
damage: *wlr.OutputDamage,

frame: wl.Listener(*wlr.OutputDamage) = wl.Listener(*wlr.OutputDamage).init(handleFrame),
destroy: wl.Listener(*wlr.Output) = wl.Listener(*wlr.Output).init(handleDestroy),

// This callback prepares the output object to accept listeners.
pub fn init(self: *Self, wlr_output: *wlr.Output) void {
    // Configure the output detected by the backend to use our allocator and renderer.
    if (!wlr_output.initRender(server.wlr_allocator, server.wlr_renderer)) return;

    // Some backends don't have modes. DRM+KMS does, and we need to set a mode before using the target.
    if (wlr_output.preferredMode()) |mode| {
        wlr_output.setMode(mode);
        wlr_output.enable(true);
        wlr_output.commit() catch return;
    }

    self.* = .{
        .server = server,
        .wlr_output = wlr_output,
        .damage = wlr.OutputDamage.create(wlr_output) catch return,
    };

    self.wlr_output.data = @ptrToInt(&self);

    // Add a callback for the frame event from the output struct.
    self.damage.events.frame.add(&self.frame);

    // Add the new output to the output_layout for automatic layout management by wlroots.
    self.server.wlr_output_layout.addAuto(self.wlr_output);
    self.server.outputs.append(allocator, self) catch {
        log.err("Failed to allocate memory.", .{});
        return;
    };
}

// This callback is called everytime an output is ready to display a frame.
fn handleFrame(listener: *wl.Listener(*wlr.OutputDamage), _: *wlr.OutputDamage) void {
    // Get the parent struct, Output.
    const self = @fieldParentPtr(Self, "frame", listener);

    // Get the scene output with respect to the wlr.Output object that's being passed.
    const scene_output = self.server.wlr_scene.getSceneOutput(self.wlr_output).?;

    // Commit the output to the scene.
    _ = scene_output.commit();

    // Get current time as the FrameDone event requires it.
    var now: os.timespec = undefined;
    os.clock_gettime(os.CLOCK.MONOTONIC, &now) catch {
        log.err("CLOCK_MONOTONIC not supported", .{});
        return;
    };

    // Send the FrameDone event.
    scene_output.sendFrameDone(&now);
}

// This callback is called everytime an output is unplugged.
fn handleDestroy(listener: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
    // Get the parent struct, Output.
    const self = @fieldParentPtr(Self, "destroy", listener);

    // Remove the output from the global compositor output layout.
    self.server.wlr_output_layout.remove(wlr_output);

    // Find index of self from outputs and remove it.
    if (std.mem.indexOfScalar(*Self, self.server.outputs.items, self)) |i| {
        _ = self.server.outputs.orderedRemove(i);
    }
    //TODO: Move closed monitors clients to focused one.
}

// Helper to get X, Y coordinates and the width and height of the output.
pub fn getGeometry(self: *Self) [4]u64 {
    var width: c_int = undefined;
    var height: c_int = undefined;
    var x: f64 = undefined;
    var y: f64 = undefined;

    self.server.wlr_output_layout.outputCoords(self.wlr_output, &x, &y);
    self.wlr_output.effectiveResolution(&width, &height);
    return [_]u64{ @floatToInt(u64, x), @floatToInt(u64, y), @intCast(u64, width), @intCast(u64, height) };
}
