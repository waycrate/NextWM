// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// nextctl.zig
//
// Created by:	Aakash Sen Sharma, September 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();
const std = @import("std");
const allocator = @import("build.zig").allocator;
const nextctl_c = @import("nextctl/build.zig");

pub const BuildType = enum {
    c,
    go,
    rust,
};

step: std.build.Step,
build_type: BuildType,
version: []const u8,

pub fn create(builder: *std.Build, build_type: BuildType, version: []const u8) !*Self {
    const self = try allocator.create(Self);
    self.* = .{
        .step = std.build.Step.init(.{
            .id = .custom,
            .name = "Build nextctl",
            .makeFn = &make,
            .owner = builder,
        }),
        .build_type = build_type,
        .version = version,
    };

    return self;
}

fn make(step: *std.build.Step, _: *std.Progress.Node) anyerror!void {
    const self = @fieldParentPtr(Self, "step", step);
    const builder = self.step.owner;

    switch (self.build_type) {
        .c => {
            try syncVersion("#define VERSION ", "nextctl/include/nextctl.h", self.version);
            _ = builder.exec(&.{ "make", "-C", "nextctl" });
        },
        .rust => {
            try syncVersion("version = ", "nextctl-rs/Cargo.toml", self.version);
            _ = builder.exec(&.{ "make", "-C", "nextctl-rs" });
        },
        .go => {
            try syncVersion("const VERSION = ", "nextctl-go/cmd/nextctl/nextctl.go", self.version);
            _ = builder.exec(&.{ "make", "-C", "nextctl-go" });
        },
    }
}

pub fn install(self: *Self) !void {
    const builder = self.step.owner;
    builder.getInstallStep().dependOn(&self.step);

    switch (self.build_type) {
        .c => {
            builder.installFile("./nextctl/zig-out/bin/nextctl", "bin/nextctl");
        },
        .rust => {
            builder.installFile("./nextctl-rs/target/release/nextctl", "bin/nextctl");
        },
        .go => {
            builder.installFile("./nextctl-go/nextctl", "bin/nextctl");
        },
    }
}

fn syncVersion(needle: []const u8, file_name: []const u8, new_version: []const u8) !void {
    const file = try std.fs.cwd().openFile(file_name, .{});
    defer file.close();

    const file_size = (try file.stat()).size;
    const file_buffer = try file.readToEndAlloc(allocator, file_size);
    defer allocator.free(file_buffer);

    const start_index = std.mem.indexOfPos(u8, file_buffer, 0, needle).? + needle.len;
    const end_index = std.mem.indexOfPos(u8, file_buffer, start_index + 1, "\"").? + 1;
    const old_version = file_buffer[start_index..end_index];

    const old_version_str = try std.fmt.allocPrint(allocator, "{s}{s}\n", .{ needle, old_version });
    defer allocator.free(old_version_str);

    const new_version_str = try std.fmt.allocPrint(allocator, "{s}\"{s}\"\n", .{ needle, new_version });
    defer allocator.free(new_version_str);

    const replaced_str = try std.mem.replaceOwned(u8, allocator, file_buffer, old_version_str, new_version_str);
    defer allocator.free(replaced_str);

    try std.fs.cwd().writeFile(file_name, replaced_str);
}
