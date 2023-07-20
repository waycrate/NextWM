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
const c = @import("../utils/c.zig");
const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Server = @import("../Server.zig");
const Wallpaper = @import("Wallpaper.zig");

pub const WallpaperMode = enum {
    fit,
    stretch,
};

server: *Server,

wlr_output: *wlr.Output,

background_image_surface: ?*c.cairo_surface_t = null,

has_wallpaper: bool = false,
wallpaper: ?*Wallpaper = null,
wallpaper_path: ?[]const u8 = null,
wallpaper_mode: ?WallpaperMode = null,

frame: wl.Listener(*wlr.Output) = wl.Listener(*wlr.Output).init(handleFrame),
destroy: wl.Listener(*wlr.Output) = wl.Listener(*wlr.Output).init(handleDestroy),

// This callback prepares the output object to accept listeners.
pub fn init(self: *Self, wlr_output: *wlr.Output) !void {
    log.debug("Initializing output device", .{});

    // Configure the output detected by the backend to use our allocator and renderer.
    if (!wlr_output.initRender(server.wlr_allocator, server.wlr_renderer)) {
        return error.OutputInitRenderFailed;
    }

    // Some backends don't have modes. DRM+KMS does, and we need to set a mode before using the target.
    if (wlr_output.preferredMode()) |preferred_mode| {
        wlr_output.setMode(preferred_mode);
        wlr_output.enable(true);
        // If preferred_mode setting failed then we iterate over all possible modes and attempt to set one.
        // If we set one succesfully then we break the loop!
        wlr_output.commit() catch {
            var iterator = wlr_output.modes.iterator(.forward);
            while (iterator.next()) |mode| {
                if (mode == preferred_mode) continue;
                wlr_output.setMode(mode);
                wlr_output.commit() catch continue;
                break;
            }
        };
    }

    //TODO: self.wlr_output.enableAdaptiveSync(true); if config states it.

    self.* = .{
        .server = server,
        .wlr_output = wlr_output,
    };

    self.wlr_output.data = @ptrToInt(&self);

    // Add a callback for the frame event from the output struct.
    self.wlr_output.events.frame.add(&self.frame);

    // Add the new output to the output_layout for automatic layout management by wlroots.
    self.server.output_layout.wlr_output_layout.addAuto(self.wlr_output);
    self.server.outputs.append(allocator, self) catch {
        return error.OOM;
    };

    const output_title = std.fmt.allocPrintZ(allocator, "nextwm - {s}", .{self.wlr_output.name}) catch |e| {
        log.err("Failed to allocate output name, skipping setting custom output name: {s}", .{@errorName(e)});
        return;
    };
    defer allocator.free(output_title);

    if (self.wlr_output.isWl()) {
        self.wlr_output.wlSetTitle(output_title);
    } else if (wlr.config.has_x11_backend and self.wlr_output.isX11()) {
        self.wlr_output.x11SetTitle(output_title);
    }

    // If focused_output is null, we become the new focused_output :)
    if (self.server.seat.focused_output) |_| {} else {
        self.server.seat.focusOutput(self);
    }
}

pub fn init_wallpaper_rendering(self: *Self) !void {
    // We do some cleanup first.
    const wallpaper_path = allocator.dupe(u8, self.wallpaper_path.?) catch return error.OOM;

    self.deinit_wallpaper();
    self.wallpaper_path = wallpaper_path;

    const image_surface = try Wallpaper.cairo_load_image(self.wallpaper_path.?);
    errdefer c.cairo_surface_destroy(image_surface);

    const output_geometry = self.getGeometry();

    self.background_image_surface = try Wallpaper.cairo_surface_transform_apply(image_surface, self.wallpaper_mode.?, output_geometry.width, output_geometry.height);

    const data = c.cairo_image_surface_get_data(self.background_image_surface);
    const stride = c.cairo_image_surface_get_stride(self.background_image_surface);

    self.wallpaper = allocator.create(Wallpaper) catch {
        log.debug("Failed to allocate memory", .{});
        log.debug("Skipping wallpaper setting", .{});
        return error.OOM;
    };

    try self.wallpaper.?.cairo_buffer_create(@intCast(c_int, output_geometry.width), @intCast(c_int, output_geometry.height), @intCast(usize, stride), data);
    errdefer allocator.destroy(self.wallpaper.?);

    self.wallpaper.?.scene_buffer = try self.server.layer_bg.createSceneBuffer(&self.wallpaper.?.base_buffer);
    self.wallpaper.?.scene_buffer.?.node.setPosition(@intCast(c_int, output_geometry.x), @intCast(c_int, output_geometry.y));
}

pub fn deinit_wallpaper(self: *Self) void {
    if (self.wallpaper) |wallpaper| {
        if (wallpaper.scene_buffer) |scene_buffer| {
            scene_buffer.node.destroy();
        }

        if (!wallpaper.base_buffer.dropped) {
            log.warn("Wallpaper deinit called before wlr_buffer_destroy", .{});
            wallpaper.base_buffer.drop();
        }

        allocator.destroy(wallpaper);
        if (self.wallpaper_path) |path| {
            allocator.free(path);
            self.wallpaper_path = null;
        }
        self.wallpaper = null;
    }

    if (self.background_image_surface) |surface| {
        c.cairo_surface_destroy(surface);
        self.background_image_surface = null;
    }
}

// This callback is called everytime an output is ready to display a frame.
fn handleFrame(listener: *wl.Listener(*wlr.Output), _: *wlr.Output) void { // Get the parent struct, Output.
    const self = @fieldParentPtr(Self, "frame", listener);
    log.debug("Signal: wlr_output_frame", .{});

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
fn handleDestroy(listener: *wl.Listener(*wlr.Output), _: *wlr.Output) void {
    // Get the parent struct, Output.
    const self = @fieldParentPtr(Self, "destroy", listener);
    log.debug("Signal: wlr_output_destroy", .{});

    self.deinit();
}

pub fn deinit(self: *Self) void {
    log.err("Deinitializing output: {s}", .{self.getName()});

    //TODO: Check if all such cases are handled in server cleanup and then in the handleDestroy.
    // Free all wallpaper surfaces and cairo objects.
    self.deinit_wallpaper();

    // Remove the output from the global compositor output layout.
    self.server.output_layout.wlr_output_layout.remove(self.wlr_output);

    // Find index of self from outputs and remove it.
    if (std.mem.indexOfScalar(*Self, self.server.outputs.items, self)) |i| {
        log.err("Removing output from server output array", .{});

        allocator.destroy(self.server.outputs.swapRemove(i));
    }

    //TODO: Move closed monitors clients to focused one.
    if (self.server.seat.focused_output) |focused_output| {
        if (focused_output.wlr_output == self.wlr_output) {
            // Unset focused output. It will be reset in output_layout_change as destroying a monitor does emit that event.
            self.server.seat.focused_output = null;
        }
    }
}

// Helper to get X, Y coordinates and the width and height of the output.
pub fn getGeometry(self: *Self) struct { width: u64, height: u64, x: u64, y: u64 } {
    var width: c_int = undefined;
    var height: c_int = undefined;
    var x: f64 = undefined;
    var y: f64 = undefined;

    self.server.output_layout.wlr_output_layout.outputCoords(self.wlr_output, &x, &y);
    self.wlr_output.effectiveResolution(&width, &height);

    return .{
        .width = @intCast(u64, width),
        .height = @intCast(u64, height),
        .x = @floatToInt(u64, x),
        .y = @floatToInt(u64, y),
    };
}

pub fn getDescription(self: *Self) [*:0]const u8 {
    if (self.wlr_output.description) |description| {
        return description;
    } else {
        return "<No output description found>";
    }
}

pub fn getMake(self: *Self) [*:0]const u8 {
    if (self.wlr_output.make) |make| {
        return make.*;
    } else {
        return "<No output make found>";
    }
}

pub fn getName(self: *Self) []const u8 {
    const name = self.wlr_output.name;
    return std.mem.span(name);
}
