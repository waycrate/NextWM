// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// nextctl.zig
//
// Created by:	Aakash Sen Sharma, October 2023
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const std = @import("std");
const allocator = @import("build.zig").allocator;

pub fn syncVersion(needle: []const u8, file_name: []const u8, new_version: []const u8) !void {
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
