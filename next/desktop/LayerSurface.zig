// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/desktop/LayerSurface.zig
//
// Created by:	Aakash Sen Sharma, August 2023
// Copyright:	(C) 2023, Aakash Sen Sharma & Contributors

const Self = @This();

const allocator = @import("../utils/allocator.zig").allocator;
const log = std.log.scoped(.LayerSurface);
const server = &@import("../next.zig").server;
const std = @import("std");

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");

const Output = @import("Output.zig");

output: *Output,
mapped: bool = false,

wlr_layer_surface: *wlr.LayerSurfaceV1,
scene_layer_surface: *wlr.SceneLayerSurfaceV1,
scene_tree: *wlr.SceneTree,
popup_scene_tree: *wlr.SceneTree,

destroy: wl.Listener(*wlr.LayerSurfaceV1) = wl.Listener(*wlr.LayerSurfaceV1).init(handleDestroy),
map: wl.Listener(*wlr.LayerSurfaceV1) = wl.Listener(*wlr.LayerSurfaceV1).init(handleMap),
unmap: wl.Listener(*wlr.LayerSurfaceV1) = wl.Listener(*wlr.LayerSurfaceV1).init(handleUnmap),
commit: wl.Listener(*wlr.Surface) = wl.Listener(*wlr.Surface).init(handleCommit),
//new_popup: wl.Listener(*wlr.XdgPopup) = wl.Listener(*wlr.XdgPopup).init(handleNewPopup),

pub fn init(wlr_layer_surface: *wlr.LayerSurfaceV1) error{OutOfMemory}!void {
    const layer_surface_output = @intToPtr(*Output, wlr_layer_surface.output.?.data);

    const self = try allocator.create(Self);
    errdefer allocator.destroy(self);

    var layer_tree: *wlr.SceneTree = undefined;
    switch (wlr_layer_surface.current.layer) {
        .background => {
            layer_tree = server.layer_bg;
        },
        .bottom => {
            layer_tree = server.layer_bottom;
        },
        .top => {
            layer_tree = server.layer_top;
        },
        .overlay => {
            layer_tree = server.layer_overlay;
        },
        else => {},
    }

    const scene_layer_surface = try layer_tree.createSceneLayerSurfaceV1(wlr_layer_surface);
    const popup_scene_tree = try layer_tree.createSceneTree();
    wlr_layer_surface.surface.data = @ptrToInt(popup_scene_tree);

    self.* = .{
        .output = layer_surface_output,
        .wlr_layer_surface = wlr_layer_surface,
        .scene_layer_surface = scene_layer_surface,
        .scene_tree = scene_layer_surface.tree,
        .popup_scene_tree = popup_scene_tree,
    };

    self.scene_tree.node.data = @ptrToInt(self);

    wlr_layer_surface.data = @ptrToInt(self);

    wlr_layer_surface.events.destroy.add(&self.destroy);
    wlr_layer_surface.events.map.add(&self.map);
    wlr_layer_surface.events.unmap.add(&self.unmap);

    handleCommit(&self.commit, wlr_layer_surface.surface);

    // Temporarily set layers state to pending so we can arrange it easily.
    const previous_state = wlr_layer_surface.current;
    wlr_layer_surface.current = wlr_layer_surface.pending;
    self.mapped = true;
    //TODO: arrangelayers.
    wlr_layer_surface.current = previous_state;
}

fn handleMap(listener: *wl.Listener(*wlr.LayerSurfaceV1), wlr_layer_surface: *wlr.LayerSurfaceV1) void {
    const self = @fieldParentPtr(Self, "map", listener);
    log.debug("Signal: wlr_layer_surface_v1_map", .{});
    log.debug("Layer surface '{s}' mapped", .{wlr_layer_surface.namespace});

    _ = self;
}

fn handleUnmap(_: *wl.Listener(*wlr.LayerSurfaceV1), _: *wlr.LayerSurfaceV1) void {}
fn handleDestroy(listener: *wl.Listener(*wlr.LayerSurfaceV1), _: *wlr.LayerSurfaceV1) void {
    const self = @fieldParentPtr(Self, "destroy", listener);
    log.debug("Signal: wlr_layer_surface_v1_destroy", .{});

    self.destroy.link.remove();
    self.map.link.remove();
    self.unmap.link.remove();

    //TODO: Destroy all popups here.

    allocator.destroy(self);
}

fn handleCommit(listener: *wl.Listener(*wlr.Surface), _: *wlr.Surface) void {
    const self = @fieldParentPtr(Self, "commit", listener);
    log.debug("Signal: wlr_surface_commit", .{});

    _ = self;
}
