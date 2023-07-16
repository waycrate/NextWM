// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/control/outputs.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const std = @import("std");
const server = &@import("../next.zig").server;
const allocator = @import("../utils/allocator.zig").allocator;
const log = std.log.scoped(.OutputControl);

const Error = @import("command.zig").Error;

const WallpaperKind = enum {
    unset,
    set,
};
const WallpaperMode = @import("../desktop/Output.zig").WallpaperMode;

pub fn listOutputs(
    args: []const [:0]const u8,
    out: *?[]const u8,
) !void {
    if (args.len > 1) return Error.TooManyArguments;

    var data = std.ArrayList(u8).init(allocator);
    const writer = data.writer();

    for (server.outputs.items) |output| {
        const geometry = output.getGeometry();
        //TODO: See what is dpmsStatus
        //TODO: Add model, serial, scale, transform, focused_status, vrr, refresh rate
        try writer.print("{s}\n\t{d}x{d} at {d},{d}\n\tScale: {d}\n\tName: {s}\n\tDescription: {s}\n\tMake: {s}\n\tEnabled: {d}\n\tVRR: {d}\n", .{
            output.wlr_output.name,
            geometry.width,
            geometry.height,
            geometry.x,
            geometry.y,
            output.wlr_output.scale,
            output.getName(),
            output.getDescription(),
            output.getMake(),
            @boolToInt(output.wlr_output.enabled),
            @boolToInt(output.wlr_output.adaptive_sync_status == .enabled),
        });
    }
    out.* = data.toOwnedSlice();
}

pub fn setWallpaper(
    args: []const [:0]const u8,
    out: *?[]const u8,
) !void {
    const state = std.meta.stringToEnum(WallpaperKind, args[1]) orelse return Error.UnknownOption;

    if (state == .unset) {
        if (args.len > 3) return error.TooManyArguments;
        if (args.len < 3) return error.NotEnoughArguments;
    } else {
        if (args.len > 5) return error.TooManyArguments;
        if (args.len < 5) return error.NotEnoughArguments;
    }

    for (server.outputs.items) |output| {
        if (std.mem.eql(u8, output.getName(), std.mem.span(args[2]))) {
            switch (state) {
                .set => {
                    output.has_wallpaper = true;
                    output.wallpaper_mode = std.meta.stringToEnum(WallpaperMode, args[3]) orelse return Error.UnknownOption;
                    output.wallpaper_path = allocator.dupe(u8, std.mem.span(args[4])) catch return Error.OutOfMemory;
                    output.init_wallpaper_rendering() catch |err| {
                        log.err("Wallpaper setting failed: {s}", .{@errorName(err)});
                        out.* = try std.fmt.allocPrint(allocator, "Wallpaper render failed: {s}\n", .{@errorName(err)});
                    };
                },

                .unset => {
                    output.deinit_wallpaper();
                    output.has_wallpaper = false;
                },
            }
        }
    }
}
