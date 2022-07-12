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

pub fn init() Self {
    log.debug("Initialized compositor config", .{});
    var self = .{};
    errdefer self.deinit();

    //TODO: Eventually if we add things that need to be freed, we must create a deinit function.

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
