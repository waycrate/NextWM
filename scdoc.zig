const std = @import("std");

pub const ScdocStep = struct {
    const scd_paths = [_][]const u8{
        "./docs/next.1.scd",
        "./docs/nextctl.1.scd",
    };

    builder: *std.build.Builder,
    step: std.build.Step,

    pub fn create(builder: *std.build.Builder) *ScdocStep {
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

    pub fn install(self: *ScdocStep) !void {
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
