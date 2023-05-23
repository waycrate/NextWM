// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/desktop/Output.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const allocator = @import("../utils/allocator.zig").allocator;
const log = std.log.scoped(.Output);
const server = &@import("../next.zig").server;
const std = @import("std");
const os = std.os;

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const pixman = @import("pixman");

const Server = @import("../Server.zig");
const NextRenderer = @import("../renderer/NextRenderer.zig");

server: *Server,
non_desktop: bool,

wlr_output: *wlr.Output,
damage_ring: wlr.DamageRing = undefined,
next_renderer: *NextRenderer = undefined,

width: c_int = 0,
height: c_int = 0,

refresh_rate: f32 = 60.0,
refresh_nsec: isize = 0,
max_render_time: u32 = 0,
last_presentation: os.timespec = undefined,

frame: wl.Listener(*wlr.Output) = wl.Listener(*wlr.Output).init(handleFrame),
present: wl.Listener(*wlr.Output.event.Present) = wl.Listener(*wlr.Output.event.Present).init(handlePresent),
destroy: wl.Listener(*wlr.Output) = wl.Listener(*wlr.Output).init(handleDestroy),

// This callback prepares the output object to accept listeners.
pub fn init(self: *Self, wlr_output: *wlr.Output) void {
    // Creating the Output object.
    self.* = .{
        .server = server,
        .wlr_output = wlr_output,
        .non_desktop = wlr_output.non_desktop,
        .width = wlr_output.width,
        .height = wlr_output.height,
    };
    wlr.DamageRing.init(&self.damage_ring);

    if (self.wlr_output.isHeadless()) {
        log.debug("Offered wl_output is headless!", .{});
    }

    // Non-desktop is only set when the output not a part of a standard desktop such as a VR output.
    log.debug("Initializing output device {s}: (non-desktop: {any})", .{
        self.wlr_output.name,
        self.wlr_output.non_desktop,
    });

    // Attempting to offer non-desktop outputs to drm_lease_manager.
    if (self.wlr_output.non_desktop) {
        self.wlr_output.events.destroy.add(&self.destroy);
        if (self.server.wlr_drm_lease_manager) |drm_lease_manager| {
            if (!drm_lease_manager.offerOutput(self.wlr_output)) {
                log.err("Failed to offer output to drm_lease_manager!", .{});
            }
        }

        self.server.non_desktop_outputs.append(allocator, self) catch {
            log.err("Failed to allocate memory.", .{});
            return;
        };
        return;
    }

    // Configure the output detected by the backend to use our allocator and renderer.
    if (!self.wlr_output.initRender(self.server.wlr_allocator, self.server.wlr_renderer)) {
        log.err("Failed to init output render,", .{});
        return;
    }

    // Some backends don't have modes. DRM+KMS does, and we need to set a mode before using the target.
    if (self.wlr_output.preferredMode()) |preferred_mode| {
        self.wlr_output.setMode(preferred_mode);
        self.wlr_output.enable(true);
        // If preferred_mode setting failed then we iterate over all possible modes and attempt to set one.
        // If we set one succesfully then we break the loop!
        self.wlr_output.commit() catch {
            var iterator = self.wlr_output.modes.iterator(.forward);
            while (iterator.next()) |mode| {
                if (mode == preferred_mode) continue;
                self.wlr_output.setMode(mode);
                self.wlr_output.commit() catch continue;
                self.refresh_rate = @intToFloat(f32, mode.refresh) / 100.0;
                break;
            }
        };
        //TODO: Should we let users choose custom formats with custom refresh rates?
        self.refresh_rate = @intToFloat(f32, preferred_mode.refresh) / 100.0;
    }

    self.wlr_output.data = @ptrToInt(&self);

    //TODO: If config states that output should have adaptive_sync then:
    //      self.wlr_output.enableAdaptiveSync(true);

    const egl = self.server.wlr_renderer.getEgl() catch {
        log.err("Failed to query renderer_EGL!", .{});
        return;
    };

    self.next_renderer = NextRenderer.init(egl) catch {
        log.err("Failed to create NextRenderer", .{});
        return;
    };

    // Add the new output to the output_layout for automatic layout management by wlroots.
    self.server.output_layout.wlr_output_layout.addAuto(self.wlr_output);
    self.server.outputs.append(allocator, self) catch {
        log.err("Failed to allocate memory.", .{});
        return;
    };

    self.wlr_output.effectiveResolution(&self.width, &self.height);
    self.damage_ring.setBounds(self.width, self.height);
    // TODO: Set `cursor scale` (look at river for inspiration)
    // TODO: Init all signals.
    // TODO: output_repaint_timer_handler

    // TODO: Get output config
    // TODO: If the output config says it should be disabled.
    // TODO: Apply output config
    // TODO: Free output config

    // TODO: Proper configuration.
    // TODO: Update OutputManagerConfig

    // TODO: Finish this destroy event handler.
    self.wlr_output.events.destroy.add(&self.destroy);

    // TODO: Finish this frame event handler.
    self.wlr_output.events.frame.add(&self.frame);
    self.wlr_output.events.present.add(&self.present);

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
}

fn handlePresent(listener: *wl.Listener(*wlr.Output.event.Present), event: *wlr.Output.event.Present) void {
    const self = @fieldParentPtr(Self, "present", listener);
    log.debug("Signal: wlr_output_present", .{});

    if (!self.wlr_output.enabled or !event.presented) {
        return;
    }

    self.last_presentation = event.when.*;
    self.refresh_nsec = event.refresh;
}

//This callback is called everytime an output is ready to display a frame.
//TODO: Finish this, look at river and sways implementation.
fn handleFrame(listener: *wl.Listener(*wlr.Output), _: *wlr.Output) void {
    const self = @fieldParentPtr(Self, "frame", listener);
    log.debug("Signal: wlr_output_frame", .{});

    if (!self.wlr_output.enabled) {
        log.debug("Skipping frame signal: {s} is disabled", .{self.wlr_output.name});
        return;
    }

    // Compute predicted milliseconds until the next refresh. It's used for delaying
    // booth output rendering and surface frame callbacks.
    var msec_until_refresh: isize = 0;

    if (self.max_render_time != 0) {
        const presentation_clock = self.server.wlr_backend.getPresentationClock();
        var now: os.timespec = undefined;
        os.clock_gettime(presentation_clock, &now) catch |e| {
            log.err("Failed to gettime: {s}", .{@errorName(e)});
            return;
        };

        const NSEC_IN_SECONDS: isize = 1000000000;
        var predicted_refresh_rate = self.last_presentation;
        predicted_refresh_rate.tv_nsec += @mod(self.refresh_nsec, NSEC_IN_SECONDS);
        predicted_refresh_rate.tv_sec += @divExact(self.refresh_nsec, NSEC_IN_SECONDS);

        if (predicted_refresh_rate.tv_nsec >= NSEC_IN_SECONDS) {
            predicted_refresh_rate.tv_sec += 1;
            predicted_refresh_rate.tv_nsec += NSEC_IN_SECONDS;
        }

        // If the predicted refresh time is before the current time then there's no point in delaying
        //
        // We only check tv_sec because if the predicted refresh time is less than a second before the current time,
        // then then msec_until_refresh will end up slightly below zero, which will effectively disable the delay without
        // poential disastrous negatve overflows that could occur if tv_sec was not checked.
        if (predicted_refresh_rate.tv_sec >= now.tv_sec) {
            const nsec_until_refresh = (predicted_refresh_rate.tv_sec - now.tv_sec) * NSEC_IN_SECONDS + (predicted_refresh_rate.tv_nsec - now.tv_nsec);
            msec_until_refresh = @divExact(nsec_until_refresh, 1000000);
        }
    }

    const delay = msec_until_refresh - self.max_render_time;
    if (delay < 1) {
        // output_repaint_timer_handler(output);

        var buffer_age: c_int = undefined;
        self.wlr_output.attachRender(&buffer_age) catch {
            log.err("Failed to attach the renderer framebuffer to wlr_output: {s}!", .{self.wlr_output.name});
            return;
        };

        var damage_region: pixman.Region32 = undefined;
        damage_region.init();
        defer damage_region.deinit();

        self.damage_ring.getBufferDamage(buffer_age, &damage_region);
        if (!self.wlr_output.needs_frame and !damage_region.notEmpty()) {
            log.debug("DamageRing was empty. Rolling back wlr_output: {s}", .{self.wlr_output.name});
            self.wlr_output.rollback();
            return;
        }

        //TODO: Some workspace init logic needs to go here. I don't want to handle workspaces just yet.
        var extended_damage: pixman.Region32 = undefined;
        extended_damage.init();
        defer extended_damage.deinit();

        //TODO: Check sway impl, some fullscreen container logic goes here? Not really sure.
        var monitor_box: wlr.Box = self.getGeometryBox();
        monitor_box.transform(&monitor_box, wlr.Output.transformInvert(self.wlr_output.transform), monitor_box.width, monitor_box.height);

        //TODO: This is where rendering begins:
        self.next_renderer.begin(monitor_box.width, monitor_box.height) catch {
            log.err("Failed to start NextRenderer!", .{});
        };

        var now: os.timespec = undefined;
        os.clock_gettime(os.CLOCK.MONOTONIC, &now) catch {
            log.err("CLOCK_MONOTONIC not supported", .{});
            return;
        };

        // Loop over all views and send their frame signal
    } else {
        self.wlr_output.frame_pending = true;
        // update the output_repaint_timer_handler
    }
}

// This callback is called everytime an output is unplugged.
fn handleDestroy(listener: *wl.Listener(*wlr.Output), wlr_output: *wlr.Output) void {
    const self = @fieldParentPtr(Self, "destroy", listener);
    log.debug("Signal: wlr_output_destroy", .{});

    // Remove the output from the global compositor output layout.
    if (!self.non_desktop) {
        self.server.output_layout.wlr_output_layout.remove(wlr_output);
    }

    var output_arr = blk: {
        if (self.non_desktop) {
            break :blk &self.server.non_desktop_outputs;
        } else {
            break :blk &self.server.outputs;
        }
    };

    if (std.mem.indexOfScalar(*Self, output_arr.items, self)) |i| {
        const output = output_arr.swapRemove(i);
        if (self.non_desktop) {
            self.next_renderer.destroy();
            log.debug("Destroyed NextRenderer!", .{});
        }
        allocator.destroy(output);
    }
    log.info("Destroyed {s} output", .{wlr_output.name});
    //TODO: Move closed monitors clients to focused one.
    //TODO: Global TODO, we should remove all output.destroy.link.remove() of the same nature. We should remove them all.
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

// Only exists for rendering contexts
pub fn getGeometryBox(self: *Self) wlr.Box {
    var width: c_int = undefined;
    var height: c_int = undefined;

    self.wlr_output.transformedResolution(&width, &height);

    return .{
        .x = 0,
        .y = 0,
        .width = width,
        .height = height,
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
