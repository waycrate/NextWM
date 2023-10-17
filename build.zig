// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// build.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const std = @import("std");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = gpa.allocator();

const Scdoc = @import("scdoc.zig");
const Nextctl = @import("nextctl.zig");
const Scanner = @import("deps/zig-wayland/build.zig").Scanner;

const version = "0.1.0-dev";

pub fn build(builder: *std.Build) !void {
    defer _ = gpa.deinit();
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});

    const xwayland = builder.option(bool, "xwayland", "Set to true to enable XWayland features.") orelse false;
    const xwayland_lazy = builder.option(bool, "xwayland-lazy", "Set to true to enable XWayland lazy initialization.") orelse false;

    const nextctl_rs = builder.option(bool, "nextctl-rs", "If enabled, rust version is built, else C.") orelse false;
    const nextctl_go = builder.option(bool, "nextctl-go", "If enabled, go version is built, else C.") orelse false;

    const exe = builder.addExecutable(.{
        .name = "next",
        .root_source_file = .{ .path = "next/next.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.addCSourceFile(.{
        .file = .{ .path = "./next/utils/wlr_log.c" },
        .flags = &.{ "-std=c18", "-O3" },
    }); // Zig doesn't have good var arg support

    const options = builder.addOptions();
    options.addOption([]const u8, "version", version);
    options.addOption(bool, "xwayland_lazy", xwayland_lazy);
    options.addOption(bool, "xwayland", xwayland);

    exe.addOptions("build_options", options);

    const scanner = Scanner.create(builder, .{});
    scanner.addCSource(exe); // TODO: remove: https://github.com/ziglang/zig/issues/131

    generate_protocol_files(scanner);

    // Packages:
    {
        const wayland = builder.createModule(
            .{ .source_file = scanner.result },
        );
        exe.addModule("wayland", wayland);

        const xkbcommon = builder.createModule(.{
            .source_file = .{ .path = "deps/zig-xkbcommon/src/xkbcommon.zig" },
        });
        exe.addModule("xkbcommon", xkbcommon);

        const pixman = builder.createModule(.{
            .source_file = .{ .path = "deps/zig-pixman/pixman.zig" },
        });
        exe.addModule("pixman", pixman);

        const clap = builder.createModule(.{
            .source_file = .{ .path = "deps/zig-clap/clap.zig" },
        });
        exe.addModule("clap", clap);

        const wlroots = builder.createModule(.{
            .source_file = .{ .path = "deps/zig-wlroots/src/wlroots.zig" },
            .dependencies = &.{
                .{ .name = "wayland", .module = wayland },
                .{ .name = "xkbcommon", .module = xkbcommon },
                .{ .name = "pixman", .module = pixman },
            },
        });
        exe.addModule("wlroots", wlroots);
    }

    // Links:
    {
        exe.linkLibC();
        exe.linkSystemLibrary("cairo");
        exe.linkSystemLibrary("libdrm");
        exe.linkSystemLibrary("libevdev");
        exe.linkSystemLibrary("libinput");
        exe.linkSystemLibrary("libturbojpeg");
        exe.linkSystemLibrary("libjpeg");
        exe.linkSystemLibrary("pixman-1");
        exe.linkSystemLibrary("wayland-server");
        exe.linkSystemLibrary("scenefx");
        exe.linkSystemLibrary("wlroots");
        exe.linkSystemLibrary("xkbcommon");
    }
    builder.installArtifact(exe);

    // Scdoc installation
    {
        if (blk: {
            _ = builder.findProgram(&.{"scdoc"}, &.{}) catch |err| switch (err) {
                error.FileNotFound => break :blk false,
                else => return err,
            };
            break :blk true;
        }) {
            try Scdoc.build(builder, "./docs/");
        }
    }

    // Nextctl Installation
    {
        // Abandoned nextctl step as zig build steps felt confusing and were very racy..
        // There should be an option to disable parallelized builds :(
        if (nextctl_rs and nextctl_go) {
            @panic("Please choose only 1 Nextctl Implementation.");
        } else if (nextctl_rs) {
            try Nextctl.syncVersion("version = ", "nextctl-rs/Cargo.toml", version);
            _ = builder.exec(&.{ "make", "-C", "nextctl-rs" });

            builder.installFile("./nextctl-rs/target/release/nextctl", "bin/nextctl");
        } else if (nextctl_go) {
            try Nextctl.syncVersion("const VERSION = ", "nextctl-go/cmd/nextctl/nextctl.go", version);
            _ = builder.exec(&.{ "make", "-C", "nextctl-go" });

            builder.installFile("./nextctl-go/nextctl", "bin/nextctl");
        } else {
            try Nextctl.syncVersion("#define VERSION ", "nextctl/include/nextctl.h", version);
            _ = builder.exec(&.{ "make", "-C", "nextctl" });

            builder.installFile("./nextctl/zig-out/bin/nextctl", "bin/nextctl");
        }
    }

    // Pkgconfig installation.
    {
        const write_file = std.Build.Step.WriteFile.create(builder);
        const pkgconfig_file = write_file.add("next-protocols.pc", builder.fmt(
            \\prefix={s}
            \\datadir=${{prefix}}/share
            \\pkgdatadir=${{datadir}}/next-protocols
            \\
            \\Name: next-protocols
            \\URL: https://git.sr.ht/~shinyzenith/nextwm
            \\Description: protocol files for NextWM
            \\Version: {s}
        , .{ builder.install_prefix, version }));

        builder.installFile("protocols/next-control-v1.xml", "share/next-protocols/next-control-v1.xml");
        builder.getInstallStep().dependOn(&builder.addInstallFile(
            pkgconfig_file,
            "share/pkgconfig/next-protocols.pc",
        ).step);
    }

    builder.installFile("./next.desktop", "share/wayland-sessions/next.desktop");
}

fn generate_protocol_files(scanner: *Scanner) void {
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("staging/ext-session-lock/ext-session-lock-v1.xml");
    scanner.addSystemProtocol("unstable/pointer-constraints/pointer-constraints-unstable-v1.xml");
    scanner.addSystemProtocol("unstable/pointer-gestures/pointer-gestures-unstable-v1.xml");
    scanner.addSystemProtocol("unstable/xdg-decoration/xdg-decoration-unstable-v1.xml");

    scanner.addCustomProtocol("protocols/next-control-v1.xml");
    scanner.addCustomProtocol("protocols/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml");
    scanner.addCustomProtocol("protocols/wlr-protocols/unstable/wlr-output-power-management-unstable-v1.xml");

    // Generating the bindings we require, we need to manually update this.
    scanner.generate("wl_compositor", 4);
    scanner.generate("wl_subcompositor", 1);
    scanner.generate("wl_shm", 1);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_seat", 7);
    scanner.generate("wl_data_device_manager", 3);
    scanner.generate("xdg_wm_base", 2);

    scanner.generate("zwlr_layer_shell_v1", 4);
    scanner.generate("zwlr_output_power_manager_v1", 1);
    scanner.generate("zwp_pointer_constraints_v1", 1);
    scanner.generate("zwp_pointer_gestures_v1", 3);
    scanner.generate("zxdg_decoration_manager_v1", 1);

    scanner.generate("ext_session_lock_manager_v1", 1);

    scanner.generate("next_control_v1", 1);
}
