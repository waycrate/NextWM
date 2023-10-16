const std = @import("std");

pub fn build(builder: *std.Build) !void {
    const protocols_path = "protocols";
    const include_path = "include";
    const src_path = "src";

    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});

    try generateProtocolFiles(builder, protocols_path, include_path, src_path);

    var src_files = try getFiles(builder, src_path, .file);
    defer deinitFilesList(builder, &src_files);

    const c_flags = &.{
        "-Wall",
        "-Wsign-conversion",
        "-Wunused-result",
        "-Wconversion",
        "-Wextra",
        "-Wfloat-conversion",
        "-Wformat",
        "-Wformat-security",
        "-Wno-keyword-macro",
        "-Wno-missing-field-initializers",
        "-Wno-narrowing",
        "-Wno-unused-parameter",
        "-Wno-unused-value",
        "-Wpedantic",
        "-std=c18",
        "-O3",
    };

    const exe = builder.addExecutable(.{
        .name = "nextctl",
        .target = target,
        .optimize = optimize,
    });
    exe.addCSourceFiles(src_files.items, c_flags);
    exe.addIncludePath(.{ .path = include_path });

    exe.linkLibC();
    exe.linkSystemLibrary("wayland-client");

    builder.installArtifact(exe);
}

fn getFiles(builder: *std.Build, dir_path: []const u8, file_kind: std.fs.File.Kind) !std.ArrayList([]const u8) {
    var files = std.ArrayList([]const u8).init(builder.allocator);
    var dir = try std.fs.cwd().openIterableDir(dir_path, .{
        .access_sub_paths = true,
    });

    var iterator = dir.iterate();
    while (try iterator.next()) |file| {
        if (file.kind == file_kind) {
            try files.append(try std.fmt.allocPrint(builder.allocator, "{s}/{s}", .{ dir_path, file.name }));
        }
    }

    return files;
}

fn deinitFilesList(builder: *std.Build, files: *std.ArrayList([]const u8)) void {
    for (files.items) |file| {
        builder.allocator.free(file);
    }
    files.deinit();
}

fn generateProtocolFiles(builder: *std.Build, protocols_path: []const u8, include_path: []const u8, src_path: []const u8) !void {
    var xml_files = try getFiles(builder, protocols_path, .sym_link);
    defer deinitFilesList(builder, &xml_files);

    for (xml_files.items) |xml_file| {
        // .h generation
        {
            const header_file_name = try std.mem.replaceOwned(u8, builder.allocator, xml_file, ".xml", ".h");
            defer builder.allocator.free(header_file_name);

            const header_file = try std.mem.replaceOwned(u8, builder.allocator, header_file_name, protocols_path, include_path);
            defer builder.allocator.free(header_file);

            _ = builder.exec(&.{ "wayland-scanner", "client-header", xml_file, header_file });
        }

        // .c generation
        {
            const src_file_name = try std.mem.replaceOwned(u8, builder.allocator, xml_file, ".xml", ".c");
            defer builder.allocator.free(src_file_name);

            const src_file = try std.mem.replaceOwned(u8, builder.allocator, src_file_name, protocols_path, src_path);
            defer builder.allocator.free(src_file);

            _ = builder.exec(&.{ "wayland-scanner", "private-code", xml_file, src_file });
        }
    }
}
