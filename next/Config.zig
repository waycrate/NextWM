// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/Config.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const std = @import("std");
const allocator = @import("utils/allocator.zig").allocator;
const log = std.log.scoped(.Config);

const Window = @import("desktop/Window.zig");

pub const CursorWarpMode = enum {
    disabled,
    @"on-output-change",
};

// Titles and app-id's of toplevels that should render client side decorations.
csd_app_ids: std.StringHashMapUnmanaged(void) = .{},
csd_titles: std.StringHashMapUnmanaged(void) = .{},

cursor_hide_when_typing: bool = false,
warp_cursor: CursorWarpMode = .disabled,

// Red - default border color.
border_color: [4]f32 = .{ 1, 0, 0, 1 },

repeat_rate: i32 = 100,
repeat_delay: i32 = 300,

border_width: u8 = 2,

//TODO: make these configurable
toplevel_corner_radius: c_int = 20,
toplevel_opacity: f32 = 1, // Ranges from 0 to 1
toplevel_box_shadow_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 },

focus_is_sloppy: bool = true,

pub fn init() Self {
    log.debug("Initialized compositor config", .{});
    const self = .{};
    errdefer self.deinit();

    return self;
}

pub fn csdAllowed(self: Self, window: *Window) bool {
    if (self.csd_app_ids.contains(std.mem.sliceTo(window.getAppId(), 0))) {
        return true;
    }

    if (self.csd_titles.contains(std.mem.sliceTo(window.getTitle(), 0))) {
        return true;
    }
    return false;
}

pub fn deinit(self: *Self) void {
    log.debug("Destroying server configuration allocations", .{});

    var app_id_it = self.csd_app_ids.keyIterator();
    while (app_id_it.next()) |key| allocator.free(key.*);

    var title_it = self.csd_titles.keyIterator();
    while (title_it.next()) |key| allocator.free(key.*);

    self.csd_app_ids.deinit(allocator);
    self.csd_titles.deinit(allocator);
}
