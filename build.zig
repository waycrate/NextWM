// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// build.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const std = @import("std"); // Zig standard library, duh!
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

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
    const version = "0.1.0";

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
        const scdoc = try ScdocStep.create(builder);
        try scdoc.install();
    }

    const nextctl = try NextctlStep.create(builder, if (nextctl_rs) .rust else .c, version);
    try nextctl.install();

    // Depend on scanner step to execute.
    exe.step.dependOn(&scanner.step);

    // TODO: remove when https://github.com/ziglang/zig/issues/131 is implemented
    scanner.addCSource(exe);

    // Add the required packages and link it to our project.
    exe.linkLibC();

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

const ScdocStep = struct {
    const scd_paths = [_][]const u8{
        "./docs/next.1.scd",
        "./docs/nextctl.1.scd",
    };

    builder: *std.build.Builder,
    step: std.build.Step,

    fn create(builder: *std.build.Builder) !*ScdocStep {
        const self = try allocator.create(ScdocStep);
        self.* = .{
            .builder = builder,
            .step = std.build.Step.init(.custom, "Generate man pages", allocator, make),
        };
        return self;
    }

    fn make(step: *std.build.Step) !void {
        const self = @fieldParentPtr(ScdocStep, "step", step);
        for (scd_paths) |path| {
            const cmd = try std.fmt.allocPrint(
                allocator,
                "scdoc < {s} > {s}.gz",
                .{ path, path[0..(path.len - 4)] },
            );
            _ = try self.builder.exec(&[_][]const u8{ "sh", "-c", cmd });
        }
    }

    fn install(self: *ScdocStep) !void {
        self.builder.getInstallStep().dependOn(&self.step);
        for (scd_paths) |p| {
            const path = try std.fmt.allocPrint(allocator, "{s}.gz", .{p[0..(p.len - 4)]});
            defer allocator.free(path);
            const path_no_ext = path[0..(path.len - 3)];
            const basename_no_ext = std.fs.path.basename(path_no_ext);
            const section = path_no_ext[(path_no_ext.len - 1)..];

            const output = try std.fmt.allocPrint(
                allocator,
                "share/man/man{s}/{s}.gz",
                .{ section, basename_no_ext },
            );
            defer allocator.free(output);

            self.builder.installFile(path, output);
        }
    }
};

pub const NextctlStep = struct {
    const BuildType = enum {
        c,
        rust,
    };

    builder: *std.build.Builder,
    step: std.build.Step,
    build_type: BuildType,
    version: []const u8,

    fn create(builder: *std.build.Builder, build_type: BuildType, version: []const u8) !*NextctlStep {
        const self = try allocator.create(NextctlStep);
        self.* = .{
            .builder = builder,
            .step = std.build.Step.init(.custom, "Build nextctl", allocator, make),
            .build_type = build_type,
            .version = version,
        };
        return self;
    }

    fn make(step: *std.build.Step) !void {
        const self = @fieldParentPtr(NextctlStep, "step", step);
        switch (self.build_type) {
            .c => {
                try syncVersion("#define VERSION ", "nextctl/nextctl.h", self.version);
                _ = try self.builder.exec(&[_][]const u8{ "sh", "-c", "make clean nextctl -C ./nextctl" });
            },
            .rust => {
                try syncVersion("version = ", "nextctl-rs/Cargo.toml", self.version);
                _ = try self.builder.exec(&[_][]const u8{ "sh", "-c", "cd nextctl-rs; cargo build --release" });
            },
        }
    }

    fn install(self: *NextctlStep) !void {
        self.builder.getInstallStep().dependOn(&self.step);
        switch (self.build_type) {
            .c => {
                self.builder.installFile("./nextctl/nextctl", "bin/nextctl");
            },
            .rust => {
                self.builder.installFile("./nextctl-rs/target/release/nextctl", "bin/nextctl");
            },
        }
    }

    fn syncVersion(needle: []const u8, file_name: []const u8, new_version: []const u8) !void {
        const file = try std.fs.cwd().openFile(file_name, .{ .read = true });
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
};
