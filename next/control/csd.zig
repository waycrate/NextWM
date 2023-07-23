// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/control/csd.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const allocator = @import("../utils/allocator.zig").allocator;
const assert = std.debug.assert;
const server = &@import("../next.zig").server;
const std = @import("std");

const Error = @import("command.zig").Error;
const Window = @import("../desktop/Window.zig");

const FilterKind = enum {
    @"app-id",
    title,
};

const FilterState = enum {
    add,
    remove,
};

pub fn csdToggle(
    args: []const [:0]const u8,
    _: *?[]const u8,
) Error!void {
    if (args.len > 4) return Error.TooManyArguments;
    if (args.len < 4) return Error.NotEnoughArguments;

    const state = std.meta.stringToEnum(FilterState, args[1]) orelse return Error.UnknownOption;
    const kind = std.meta.stringToEnum(FilterKind, args[2]) orelse return Error.UnknownOption;
    const map = switch (kind) {
        .@"app-id" => &server.config.csd_app_ids,
        .title => &server.config.csd_titles,
    };
    const key = args[3];
    switch (state) {
        .add => {
            const gop = try map.getOrPut(allocator, key);
            if (gop.found_existing) return;
            errdefer assert(map.remove(key));
            gop.key_ptr.* = try allocator.dupe(u8, key);
        },
        .remove => {
            if (map.fetchRemove(key)) |kv| allocator.free(kv.key);
        },
    }

    var decoration_it = server.decoration_manager.decorations.first;
    while (decoration_it) |decoration_node| : (decoration_it = decoration_node.next) {
        const xdg_toplevel_decoration = decoration_node.data.xdg_toplevel_decoration;
        const window = @intToPtr(*Window, xdg_toplevel_decoration.surface.data);

        const window_data: []const u8 = switch (kind) {
            .@"app-id" => std.mem.span(window.getAppId()),
            .title => std.mem.span(window.getTitle()),
        };

        if (std.mem.eql(u8, key, window_data)) {
            switch (state) {
                .add => {
                    _ = xdg_toplevel_decoration.setMode(.client_side);
                },
                .remove => {
                    _ = xdg_toplevel_decoration.setMode(.server_side);
                },
            }
        }
    }
}
