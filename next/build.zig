const std = @import("std");
const fmt = std.fmt;
const fs = std.fs;
const zbs = std.build;
const mem = std.mem;
const ArrayList = std.ArrayList;

pub fn build(builder: *zbs.Builder) !void {
    const wlr_path = "../deps/wlroots/";
    const executable_name = "next";
    const include_path = "include";
    const protocols_path = "protocols";
    const src_path = "src";

    const so_version_needle = "soversion = ";
    const new_so_version = 12032;
    const wlr_meson_file = "meson.build";
    try buildWlr(builder, wlr_path, wlr_meson_file, so_version_needle, new_so_version);

    const target = builder.standardTargetOptions(.{});
    const mode = builder.standardReleaseOptions();

    try generateProtocolHeaders(builder, protocols_path);

    var src_files = try getFiles(builder, src_path, .File);
    defer deinitFilesList(builder, &src_files);

    const c_flags = &[_][]const u8{
        "-Wall",
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
    };
    const cxx_flags = &[_][]const u8{"-std=c++20"} ++ c_flags;

    const exe = builder.addExecutable(executable_name, null);
    exe.setTarget(target);
    exe.setBuildMode(mode);

    exe.addCSourceFiles(src_files.items, cxx_flags);
    exe.defineCMacro("WLR_USE_UNSTABLE", null);

    exe.addIncludePath(include_path);
    exe.addIncludePath(protocols_path);
    exe.addIncludePath(wlr_path ++ "/include/wlr/");

    exe.addObjectFile(fmt.comptimePrint("{s}/build/libwlroots.so.{d}", .{ wlr_path, new_so_version }));

    exe.linkLibC();
    exe.linkLibCpp();
    exe.linkSystemLibrary("EGL");
    exe.linkSystemLibrary("gl");
    exe.linkSystemLibrary("wayland-server");
    exe.linkSystemLibrary("wayland-client");
    exe.linkSystemLibrary("wayland-cursor");
    exe.linkSystemLibrary("libdrm");
    exe.linkSystemLibrary("libinput");
    exe.linkSystemLibrary("pixman-1");
    exe.linkSystemLibrary("udev");
    exe.linkSystemLibrary("wacom");
    exe.linkSystemLibrary("wlroots");
    exe.linkSystemLibrary("xcb");
    exe.linkSystemLibrary("xkbcommon");

    exe.install();
}

fn getFiles(builder: *zbs.Builder, dir_path: []const u8, file_kind: fs.File.Kind) !ArrayList([]const u8) {
    var files = ArrayList([]const u8).init(builder.allocator);
    var dir = try std.fs.cwd().openIterableDir(dir_path, .{
        .access_sub_paths = true,
    });

    var iterator = dir.iterate();
    while (try iterator.next()) |file| {
        if (file.kind == file_kind) {
            try files.append(try fmt.allocPrint(builder.allocator, "{s}/{s}", .{ dir_path, file.name }));
        }
    }

    return files;
}

fn deinitFilesList(builder: *zbs.Builder, files: *ArrayList([]const u8)) void {
    for (files.items) |file| {
        builder.allocator.free(file);
    }
    files.deinit();
}

fn generateProtocolHeaders(builder: *zbs.Builder, protocols_path: []const u8) !void {
    var old_header_files = try getFiles(builder, protocols_path, .File);
    defer deinitFilesList(builder, &old_header_files);

    for (old_header_files.items) |header_file| {
        const protocols_dir = try fs.cwd().openDir(protocols_path, .{});
        protocols_dir.deleteFile(header_file) catch {};
    }

    var xml_files = try getFiles(builder, protocols_path, .SymLink);
    defer deinitFilesList(builder, &xml_files);

    for (xml_files.items) |xml_file| {
        const header_file = try mem.replaceOwned(u8, builder.allocator, xml_file, ".xml", "-protocol.h");
        defer builder.allocator.free(header_file);

        _ = try builder.exec(&[_][]const u8{ "wayland-scanner", "server-header", xml_file, header_file });
    }
}

fn buildWlr(builder: *zbs.Builder, comptime wlr_path: []const u8, comptime wlr_meson_file: []const u8, needle: []const u8, new_version: usize) !void {
    // Changing soversion.
    const file_path = wlr_path;
    const file_name = file_path ++ wlr_meson_file;

    const file = try std.fs.cwd().openFile(file_name, .{});
    const file_size = (try file.stat()).size;
    const file_buffer = try file.readToEndAlloc(builder.allocator, file_size);
    defer builder.allocator.free(file_buffer);

    const start_index = std.mem.indexOfPos(u8, file_buffer, 0, needle).? + needle.len;
    const end_index = std.mem.indexOfPos(u8, file_buffer, start_index + 1, "").? + 1;
    const old_version = file_buffer[start_index..end_index];

    const old_version_str = try std.fmt.allocPrint(builder.allocator, "{s}{s}\n", .{ needle, old_version });
    defer builder.allocator.free(old_version_str);

    const new_version_str = try std.fmt.allocPrint(builder.allocator, "{s}{d}\n", .{ needle, new_version });
    defer builder.allocator.free(new_version_str);

    const replaced_str = try std.mem.replaceOwned(u8, builder.allocator, file_buffer, old_version_str, new_version_str);
    defer builder.allocator.free(replaced_str);

    try std.fs.cwd().writeFile(file_name, replaced_str);

    // Compiling wlroots
    _ = try builder.exec(&[_][]const u8{ "sh", "-c", "cd " ++ wlr_path ++ "; meson setup build --reconfigure; ninja -C build" });
}
