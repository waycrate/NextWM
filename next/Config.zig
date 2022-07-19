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

const Window = @import("./desktop/Window.zig");

/// Titles and app-id's of toplevels that should render client side decorations.
csd_app_ids: std.StringHashMapUnmanaged(void) = .{},
csd_titles: std.StringHashMapUnmanaged(void) = .{},

repeat_rate: i32 = 100,
repeat_delay: i32 = 300,

border_width: u8 = 0,

pub fn init() Self {
    log.debug("Initialized compositor config", .{});
    const self = .{};
    errdefer self.deinit();

    return self;
}

pub fn csdAllowed(self: Self, window: *Window) bool {
    if (self.csd_app_ids.contains(std.mem.span(window.getAppId()))) {
        return true;
    }

    if (self.csd_titles.contains(std.mem.span(window.getTitle()))) {
        return true;
    }
    return false;
}

pub fn deinit(self: *Self) void {
    log.debug("Destroying server configuration allocations", .{});

    while (self.csd_app_ids.keyIterator().next()) |key| allocator.free(key.*);
    while (self.csd_titles.keyIterator().next()) |key| allocator.free(key.*);

    self.csd_app_ids.deinit(allocator);
    self.csd_titles.deinit(allocator);
}
