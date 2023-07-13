// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// build.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const std = @import("std");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = gpa.allocator();

const NextctlStep = @import("nextctl.zig");
const ScdocStep = @import("scdoc.zig");
const ScanProtocolsStep = @import("deps/zig-wayland/build.zig").ScanProtocolsStep;

const version = "0.1.0-dev";

pub fn build(builder: *std.build.Builder) !void {
    const target = builder.standardTargetOptions(.{});
    const build_mode = builder.standardReleaseOptions();

    const xwayland = builder.option(bool, "xwayland", "Set to true to enable XWayland features.") orelse false;
    const xwayland_lazy = builder.option(bool, "xwayland-lazy", "Set to true to enable XWayland lazy initialization.") orelse false;

    const nextctl_rs = builder.option(bool, "nextctl-rs", "If enabled, rust version is built, else C.") orelse false;
    const nextctl_go = builder.option(bool, "nextctl-go", "If enabled, go version is built, else C.") orelse false;

    const exe = builder.addExecutable("next", "next/next.zig");
    exe.setTarget(target);
    exe.setBuildMode(build_mode);
    exe.addCSourceFile("./next/utils/wlr_log.c", &[_][]const u8{ "-std=c18", "-O3" }); // Zig doesn't have good var arg support

    const options = builder.addOptions();
    options.addOption([]const u8, "version", version);
    options.addOption(bool, "xwayland_lazy", xwayland_lazy);
    options.addOption(bool, "xwayland", xwayland);

    exe.addOptions("build_options", options);

    const scanner = ScanProtocolsStep.create(builder);
    scanner.addCSource(exe); // TODO: remove: https://github.com/ziglang/zig/issues/131

    generate_protocol_files(scanner);
    exe.step.dependOn(&scanner.step);

    // Packages:
    {
        const clap = std.build.Pkg{
            .name = "clap",
            .source = .{ .path = "deps/zig-clap/clap.zig" },
        };
        exe.addPackage(clap);

        const wayland = std.build.Pkg{
            .name = "wayland",
            .source = .{ .generated = &scanner.result },
        };
        exe.addPackage(wayland);

        const pixman = std.build.Pkg{
            .name = "pixman",
            .source = .{ .path = "deps/zig-pixman/pixman.zig" },
        };
        exe.addPackage(pixman);

        const xkbcommon = std.build.Pkg{
            .name = "xkbcommon",
            .source = .{ .path = "deps/zig-xkbcommon/src/xkbcommon.zig" },
        };
        exe.addPackage(xkbcommon);

        const wlroots = std.build.Pkg{
            .name = "wlroots",
            .source = .{ .path = "deps/zig-wlroots/src/wlroots.zig" },
            .dependencies = &[_]std.build.Pkg{ wayland, xkbcommon, pixman },
        };
        exe.addPackage(wlroots);
    }

    // Links:
    {
        exe.linkLibC();
        exe.linkSystemLibrary("libevdev");
        exe.linkSystemLibrary("libinput");
        exe.linkSystemLibrary("pixman-1");
        exe.linkSystemLibrary("wayland-server");
        exe.linkSystemLibrary("wlroots");
        exe.linkSystemLibrary("xkbcommon");
    }
    exe.install();

    // Scdoc installation
    {
        if (blk: {
            _ = builder.findProgram(&[_][]const u8{"scdoc"}, &[_][]const u8{}) catch |err| switch (err) {
                error.FileNotFound => break :blk false,
                else => return err,
            };
            break :blk true;
        }) {
            try ScdocStep.build(builder, "./docs/");
        }
    }

    // Nextctl Installation
    {
        const build_type: NextctlStep.BuildType = blk: {
            if (nextctl_rs and nextctl_go) {
                @panic("Please choose only 1 Nextctl Implementation.");
            } else if (nextctl_rs) {
                break :blk .rust;
            } else if (nextctl_go) {
                break :blk .go;
            } else {
                break :blk .c;
            }
        };

        const nextctl = try NextctlStep.create(builder, build_type, version, target, build_mode);
        try nextctl.install();
    }

    // Pkgconfig installation.
    {
        const pkgconfig_file = try std.fs.cwd().createFile("next-protocols.pc", .{});
        defer pkgconfig_file.close();

        try pkgconfig_file.writer().print(
            \\prefix={s}
            \\datadir=${{prefix}}/share
            \\pkgdatadir=${{datadir}}/next-protocols
            \\
            \\Name: next-protocols
            \\URL: https://git.sr.ht/~shinyzenith/nextwm
            \\Description: protocol files for NextWM
            \\Version: {s}
        , .{ builder.install_prefix, version });

        builder.installFile("protocols/next-control-v1.xml", "share/next-protocols/next-control-v1.xml");
        builder.installFile("next-protocols.pc", "share/pkgconfig/next-protocols.pc");
    }

    builder.installFile("./next.desktop", "share/wayland-sessions/next.desktop");
}

fn generate_protocol_files(scanner: *ScanProtocolsStep) void {
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("staging/ext-session-lock/ext-session-lock-v1.xml");
    scanner.addSystemProtocol("unstable/pointer-constraints/pointer-constraints-unstable-v1.xml");
    scanner.addSystemProtocol("unstable/pointer-gestures/pointer-gestures-unstable-v1.xml");
    scanner.addSystemProtocol("unstable/xdg-decoration/xdg-decoration-unstable-v1.xml");

    scanner.addProtocolPath("protocols/next-control-v1.xml");
    scanner.addProtocolPath("protocols/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml");
    scanner.addProtocolPath("protocols/wlr-protocols/unstable/wlr-output-power-management-unstable-v1.xml");

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
