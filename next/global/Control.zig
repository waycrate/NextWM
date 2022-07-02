// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// src/global/Control.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();
const std = @import("std");

const allocator = @import("../utils/allocator.zig").allocator;
const server = &@import("../next.zig").server;

const next = @import("wayland").server.next;
const wl = @import("wayland").server.wl;

const ArgMap = std.AutoHashMap(struct { client: *wl.Client, id: u32 }, std.ArrayListUnmanaged([:0]const u8));

global: *wl.Global,
server_destroy: wl.Listener(*wl.Server) = wl.Listener(*wl.Server).init(serverDestroy),
args: ArgMap = std.AutoHashMap.init(),

pub fn init(self: *Self) !void {
    self.* = .{
        .global = try wl.Global.create(server.wl_server, next.ControlV1, 1, *Self, self, bind),
        .args = ArgMap.init(allocator),
    };

    server.wl_server.addDestroyListener(&self.server_destroy);
}

fn serverDestroy(listener: *wl.Listener(*wl.Server), _: *wl.Server) void {
    const self = @fieldParentPtr(Self, "server_destroy", listener);
    self.global.destroy();
    self.args.deinit();
}

fn bind(client: *wl.Client, self: *Self, version: u32, id: u32) callconv(.C) void {
    const control = next.ControlV1.create(client, version, id) catch {
        client.postNoMemory();
        return;
    };
    self.args.putNoClobber(.{ .client = client, .id = id }, .{}) catch {
        client.destroy();
        client.postNoMemory();
        return;
    };
    control.setHandler(*Self, handleRequest, handleDestroy, self);
}

fn handleRequest(control: *next.ControlV1, request: next.ControlV1.Request, _: *Self) void {
    switch (request) {
        .destroy => control.destroy(),
        .add_argument => |add_argument| {
            //TODO: Finish this.
            std.debug.print("{s}", .{add_argument.argument});
        },
        //TODO: Finish this
        else => {},
    }
}

fn handleDestroy(control: *next.ControlV1, self: *Self) void {
    var args = self.args.fetchRemove(
        .{ .client = control.getClient(), .id = control.getId() },
    ).?.value;
    for (args.items) |arg| allocator.free(arg);
    args.deinit(allocator);
}
