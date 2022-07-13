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

    // Create build options.
    const options = builder.addOptions();
    options.addOption([]const u8, "version", version);

    // This block keeps the zig compositor version and the nextctl.h file version in sync.
    {
        // The needle to search with.
        const needle = "#define VERSION ";

        // Get the file contents into a buffer.
        const file = try std.fs.cwd().openFile("nextctl/nextctl.h", .{ .read = true });
        const file_size = (try file.stat()).size;
        const file_buffer = try file.readToEndAlloc(allocator, file_size);
        defer allocator.free(file_buffer);

        // Find the starting index of the needle, calculate the index of the ending " from that and then
        // take a slice of the version string out.
        const start_index = std.mem.indexOfPos(u8, file_buffer, 0, needle).? + needle.len;
        const end_index = std.mem.indexOfPos(u8, file_buffer, start_index + 1, "\"").? + 1;
        const old_version = file_buffer[start_index..end_index];

        // This cannot be evaluated at comptime :(
        const old_version_str = try std.fmt.allocPrint(allocator, "{s}{s}\n", .{ needle, old_version });
        defer allocator.free(old_version_str);

        const new_version_str = std.fmt.comptimePrint("{s}\"{s}\"\n", .{ needle, version });

        // Replace old string with new one.
        const replaced_str = try std.mem.replaceOwned(u8, allocator, file_buffer, old_version_str, new_version_str);
        defer allocator.free(replaced_str);

        // Write our changes to the header file.
        try std.fs.cwd().writeFile("nextctl/nextctl.h", replaced_str);

        // Building nextctl.
        _ = try builder.exec(&[_][]const u8{ "sh", "-c", "make clean nextctl -C ./nextctl" });
    }

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
        const scdoc = ScdocStep.create(builder);
        try scdoc.install();
    }

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

    // Install the .desktop file to the prefix.
    builder.installFile("./next.desktop", "share/wayland-sessions/next.desktop");

    // Install nextctl binary to the prefix.
    builder.installFile("./nextctl/nextctl", "bin/nextctl");

    // Install the binary to the mentioned prefix.
    exe.install();
}

const ScdocStep = struct {
    const scd_paths = [_][]const u8{
        "next.1.scd",
        "nextctl.1.scd",
    };

    builder: *std.build.Builder,
    step: std.build.Step,

    fn create(builder: *std.build.Builder) *ScdocStep {
        const self = builder.allocator.create(ScdocStep) catch @panic("out of memory");
        self.* = init(builder);
        return self;
    }

    fn init(builder: *std.build.Builder) ScdocStep {
        return ScdocStep{
            .builder = builder,
            .step = std.build.Step.init(.custom, "Generate man pages", builder.allocator, make),
        };
    }

    fn make(step: *std.build.Step) !void {
        const self = @fieldParentPtr(ScdocStep, "step", step);
        for (scd_paths) |path| {
            const command = try std.fmt.allocPrint(
                self.builder.allocator,
                "scdoc < {s} > {s}",
                .{ path, path[0..(path.len - 4)] },
            );
            _ = try self.builder.exec(&[_][]const u8{ "sh", "-c", command });
        }
    }

    fn install(self: *ScdocStep) !void {
        self.builder.getInstallStep().dependOn(&self.step);

        for (scd_paths) |path| {
            const path_no_ext = path[0..(path.len - 4)];
            const basename_no_ext = std.fs.path.basename(path_no_ext);
            const section = path_no_ext[(path_no_ext.len - 1)..];

            const output = try std.fmt.allocPrint(
                self.builder.allocator,
                "share/man/man{s}/{s}",
                .{ section, basename_no_ext },
            );

            self.builder.installFile(path_no_ext, output);
        }
    }
};
