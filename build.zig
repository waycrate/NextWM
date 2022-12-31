// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// build.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const std = @import("std"); // Zig standard library, duh!

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = gpa.allocator();

const NextctlStep = @import("nextctl.zig");
const ScdocStep = @import("scdoc.zig");

pub fn build(builder: *std.build.Builder) !void {
    const ScanProtocolsStep = @import("deps/zig-wayland/build.zig").ScanProtocolsStep;

    // Creating the wayland-scanner.
    const scanner = ScanProtocolsStep.create(builder);
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("unstable/pointer-constraints/pointer-constraints-unstable-v1.xml");

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

    scanner.generate("next_control_v1", 1);

    // Version information.
    const version = "0.1.0-dev";

    // Xwayland Lazy.
    const xwayland_lazy = builder.option(bool, "xwayland-lazy", "Set to true to enable XwaylandLazy initialization") orelse false;

    // Nextctl-rs.
    const nextctl_rs = builder.option(bool, "nextctl-rs", "If enabled, rust version is built, else C.") orelse false;

    // Create build options.
    const options = builder.addOptions();

    // Adding build options which we can access in our source code.
    options.addOption([]const u8, "version", version);
    options.addOption(bool, "xwayland_lazy", xwayland_lazy);
    options.addOption(bool, "nextctl_rs", nextctl_rs);

    // Creating the executable.
    const exe = builder.addExecutable("next", "next/next.zig");

    // Attaching the build_options to the executable so it's available from the codebase.
    exe.addOptions("build_options", options);

    // Setting executable target and build mode.
    exe.setTarget(builder.standardTargetOptions(.{}));
    exe.setBuildMode(builder.standardReleaseOptions());

    // Checking if scdoc exists and accordingly adding man page generation step.
    if (blk: {
        _ = builder.findProgram(&[_][]const u8{"scdoc"}, &[_][]const u8{}) catch |err| switch (err) {
            error.FileNotFound => break :blk false,
            else => return err,
        };
        break :blk true;
    }) {
        try ScdocStep.build(builder, "./docs/");
    }

    // Compiling nextctl and installing it.
    const nextctl = try NextctlStep.create(builder, if (nextctl_rs) .rust else .c, version);
    try nextctl.install();

    // Writing pkgconfig file and installing it.
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

    // Depend on scanner step to execute.
    exe.step.dependOn(&scanner.step);

    // TODO: remove when https://github.com/ziglang/zig/issues/131 is implemented
    scanner.addCSource(exe);

    // Add the required packages and link it to our project.
    exe.linkLibC();

    // Flag parsing library.
    const clap = std.build.Pkg{
        .name = "clap",
        .path = .{ .path = "deps/zig-clap/clap.zig" },
    };
    exe.addPackage(clap);

    const wayland = std.build.Pkg{
        .name = "wayland",
        .path = .{ .generated = &scanner.result },
    };
    exe.addPackage(wayland);
    exe.linkSystemLibrary("wayland-server");

    const pixman = std.build.Pkg{
        .name = "pixman",
        .path = .{ .path = "deps/zig-pixman/pixman.zig" },
    };
    exe.addPackage(pixman);
    exe.linkSystemLibrary("pixman-1");

    const xkbcommon = std.build.Pkg{
        .name = "xkbcommon",
        .path = .{ .path = "deps/zig-xkbcommon/src/xkbcommon.zig" },
    };
    exe.addPackage(xkbcommon);
    exe.linkSystemLibrary("xkbcommon");

    const wlroots = std.build.Pkg{
        .name = "wlroots",
        .path = .{ .path = "deps/zig-wlroots/src/wlroots.zig" },
        .dependencies = &[_]std.build.Pkg{ wayland, xkbcommon, pixman },
    };
    exe.addPackage(wlroots);
    exe.linkSystemLibrary("wlroots");

    // Some other libraries we need to link with.
    exe.linkSystemLibrary("libevdev");
    exe.linkSystemLibrary("libinput");

    // Adding our log wrapper to the source file list.
    // -O3 does agressive optimizations.
    exe.addCSourceFile("./next/utils/wlr_log.c", &[_][]const u8{ "-std=c18", "-O3" });

    // Install the .desktop file to the prefix.
    builder.installFile("./next.desktop", "share/wayland-sessions/next.desktop");

    // Install the binary to the mentioned prefix.
    exe.install();
}
