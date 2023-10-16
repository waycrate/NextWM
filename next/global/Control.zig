// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/global/Control.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const std = @import("std");
const allocator = @import("../utils/allocator.zig").allocator;
const command = @import("../control/command.zig");
const server = &@import("../next.zig").server;

const wayland = @import("wayland");
const next = wayland.server.next;
const wl = wayland.server.wl;

const ArgMap = std.AutoHashMap(struct { client: *wl.Client, id: u32 }, std.ArrayListUnmanaged([:0]const u8));

global: *wl.Global,
server_destroy: wl.Listener(*wl.Server) = wl.Listener(*wl.Server).init(serverDestroy),
args: ArgMap,

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

fn bind(client: *wl.Client, self: *Self, version: u32, id: u32) void {
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

fn handleRequest(control: *next.ControlV1, request: next.ControlV1.Request, self: *Self) void {
    switch (request) {
        .destroy => control.destroy(),
        .add_argument => |add_argument| {
            const slice = allocator.dupeZ(u8, std.mem.sliceTo(add_argument.argument, 0)) catch {
                control.getClient().postNoMemory();
                return;
            };

            const arg_map = self.args.getPtr(.{ .client = control.getClient(), .id = control.getId() }).?;
            arg_map.append(allocator, slice) catch {
                control.getClient().postNoMemory();
                allocator.free(slice);
                return;
            };
        },
        .run_command => |run_command| {
            const args = self.args.getPtr(.{ .client = control.getClient(), .id = control.getId() }).?;
            defer {
                for (args.items) |arg| allocator.free(arg);
                args.items.len = 0;
            }

            const callback = next.CommandCallbackV1.create(
                control.getClient(),
                control.getVersion(),
                run_command.callback,
            ) catch {
                control.getClient().postNoMemory();
                return;
            };

            var output: ?[]const u8 = null;
            defer if (output) |s| allocator.free(s);
            command.run(args.items, &output) catch |err| {
                const failure_message = switch (err) {
                    command.Error.OutOfMemory => {
                        callback.getClient().postNoMemory();
                        return;
                    },
                    else => command.errToMsg(err),
                };
                callback.sendFailure(failure_message);
                return;
            };

            const success_message: [:0]const u8 = blk: {
                if (output) |s| {
                    break :blk allocator.dupeZ(u8, s) catch {
                        callback.getClient().postNoMemory();
                        return;
                    };
                } else break :blk "";
            };

            defer if (output != null) allocator.free(success_message);
            callback.sendSuccess(success_message);
        },
    }
}

fn handleDestroy(control: *next.ControlV1, self: *Self) void {
    var args = self.args.fetchRemove(
        .{ .client = control.getClient(), .id = control.getId() },
    ).?.value;
    for (args.items) |arg| allocator.free(arg);
    args.deinit(allocator);
}
