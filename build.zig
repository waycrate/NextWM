const std = @import("std"); // Zig standard library, duh!

pub fn build(builder: *std.build.Builder) !void {
    const ScanProtocolsStep = @import("deps/zig-wayland/build.zig").ScanProtocolsStep;

    // Creating the wayland-scanner.
    const scanner = ScanProtocolsStep.create(builder);
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");

    // Creating the executable.
    const exe = builder.addExecutable("herb", "herb/main.zig");

    // Setting executable target and build mode.
    exe.setTarget(builder.standardTargetOptions(.{}));
    exe.setBuildMode(builder.standardReleaseOptions());

    // Depend on scanner step.
    exe.step.dependOn(&scanner.step);

    scanner.addCSource(exe); // TODO: remove when https://github.com/ziglang/zig/issues/131 is implemented

    // Add the required packages and link it to our project.
    exe.linkLibC();

    exe.step.dependOn(&scanner.step);

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
    builder.installFile("./herb.desktop", "share/wayland-sessions/herb.desktop");

    // Install the .desktop file to the prefix.
    builder.installFile("./herb.desktop", "share/wayland-sessions/herb.desktop");

    // Install the binary to the mentioned prefix.
    exe.install();
}
