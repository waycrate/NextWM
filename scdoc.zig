// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// scdoc.zig
//
// Created by:	Aakash Sen Sharma, September 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const std = @import("std");
const allocator = @import("build.zig").allocator;

pub fn build(builder: *std.build.Builder, docs_dir: []const u8) !void {
    var dir = try std.fs.cwd().openDir(docs_dir, .{
        .access_sub_paths = true,
        .iterate = true,
    });
    defer dir.close();

    //TODO: https://github.com/ziglang/zig/blob/master/lib/std/compress/gzip.zig Gzip the man-pages properly

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .File) {
            if (std.mem.lastIndexOfScalar(u8, entry.name, '.')) |idx| {
                if (std.mem.eql(u8, entry.name[idx..], ".scd")) {
                    const p = try std.fmt.allocPrint(allocator, "{s}{s}", .{ docs_dir, entry.name });
                    defer allocator.free(p);

                    const path = try std.fmt.allocPrint(allocator, "{s}.gz", .{p[0..(p.len - 4)]});
                    defer allocator.free(path);

                    const path_no_ext = path[0..(path.len - 3)];
                    const section = path_no_ext[(path_no_ext.len - 1)..];

                    const output = try std.fmt.allocPrint(
                        allocator,
                        "share/man/man{s}/{s}",
                        .{ section, path },
                    );
                    defer allocator.free(output);

                    const cmd = try std.fmt.allocPrint(
                        allocator,
                        "scdoc < {s} > {s}",
                        .{ p, path },
                    );
                    defer allocator.free(cmd);
                    _ = try builder.exec(&[_][]const u8{ "sh", "-c", cmd });

                    builder.installFile(path, output);
                }
            }
        }
    }
}
