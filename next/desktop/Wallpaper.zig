// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/desktop/Wallpaper.zig
//
// Created by:	Aakash Sen Sharma, July 2023
// Copyright:	(C) 2023, Aakash Sen Sharma & Contributors

const Self = @This();

const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.Wallpaper);
const os = std.os;
const c = @import("../utils/c.zig");
const allocator = @import("../utils/allocator.zig").allocator;

const wl = @import("wayland").server.wl;
const wlr = @import("wlroots");
const endianess = builtin.target.cpu.arch.endian();

const WallpaperMode = @import("Output.zig").WallpaperMode;

base_buffer: wlr.Buffer,
data: [*c]u8,
stride: usize,
scene_buffer: ?*wlr.SceneBuffer = null,

const jpeg_magics = [_][4]u8{
    [_]u8{ 0xFF, 0xD8, 0xFF, 0xD8 },
    [_]u8{ 0xFF, 0xD8, 0xFF, 0xE0 },
    [_]u8{ 0xFF, 0xD8, 0xFF, 0xE1 },
};

const png_magic = [_]u8{ 0x89, 0x50, 0x4E, 0x47 };

pub fn cairo_load_image(path: []const u8) !*c.cairo_surface_t {
    log.debug("Loading image: {s}", .{path});
    var magic: [4]u8 = undefined;

    const fd = try os.open(path, os.linux.O.RDONLY, undefined);
    defer os.close(fd);

    const bytes_read = try os.read(fd, &magic);
    if (bytes_read != 4) {
        return error.FailedToReadMagic;
    }

    for (jpeg_magics) |jpeg_magic| {
        if (std.mem.eql(u8, &magic, &jpeg_magic)) {
            log.info("Mimetype jpg detected", .{});
            return cairo_load_jpg(path);
        }
    }

    if (std.mem.eql(u8, &magic, &png_magic)) {
        log.info("Mimetype png detected", .{});
        return cairo_load_png(path);
    }
    return error.InvalidImageFormat;
}

fn cairo_load_png(path: []const u8) !*c.cairo_surface_t {
    return c.cairo_image_surface_create_from_png(path.ptr).?;
}

fn cairo_load_jpg(path: []const u8) !*c.cairo_surface_t {
    var jpeg_error: c.jpeg_error_mgr = undefined;
    var jpeg_info: c.jpeg_decompress_struct = undefined;

    const fd = @as(c_int, @intCast(try std.os.open(path, 0 | std.os.O.RDONLY, undefined)));
    defer _ = std.os.close(fd);

    const fd_stat = try std.os.fstat(fd);

    var buf: [*c]u8 = @as([*c]u8, @ptrCast(c.malloc(@as(c_ulong, @intCast(fd_stat.size))) orelse return error.OOM));
    if (c.read(fd, buf, @as(usize, @intCast(fd_stat.size))) < fd_stat.size) {
        return error.failedToReadAllBytes;
    }

    jpeg_info.err = c.jpeg_std_error(&jpeg_error);
    c.jpeg_create_decompress(&jpeg_info);
    c.jpeg_mem_src(&jpeg_info, buf, @as(c_ulong, @intCast(fd_stat.size)));

    _ = c.jpeg_read_header(&jpeg_info, 1);

    log.info("System is {s} endian", .{@tagName(endianess)});

    if (endianess == .Little) {
        log.info("Using JCS_EXT_BGRA format", .{});
        jpeg_info.out_color_space = c.JCS_EXT_BGRA;
    } else {
        log.info("Using JCS_EXT_ARGB format", .{});
        jpeg_info.out_color_space = c.JCS_EXT_ARGB;
    }

    _ = c.jpeg_start_decompress(&jpeg_info);

    var surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_RGB24, @as(c_int, @intCast(jpeg_info.output_width)), @as(c_int, @intCast(jpeg_info.output_height)));
    if (c.cairo_surface_status(surface) != c.CAIRO_STATUS_SUCCESS) {
        c.jpeg_destroy_decompress(&jpeg_info);
        return error.cairoSurfaceCreationFailed;
    }

    while (jpeg_info.output_scanline < jpeg_info.output_height) {
        var row_address = c.cairo_image_surface_get_data(surface) + (jpeg_info.output_scanline * @as(c_uint, @intCast(c.cairo_image_surface_get_stride(surface))));

        _ = c.jpeg_read_scanlines(&jpeg_info, &row_address, 1);
    }

    c.cairo_surface_mark_dirty(surface);
    _ = c.jpeg_finish_decompress(&jpeg_info);
    c.jpeg_destroy_decompress(&jpeg_info);
    _ = c.cairo_surface_set_mime_data(surface, c.CAIRO_MIME_TYPE_JPEG, buf, @as(c_ulong, @intCast(fd_stat.size)), c.free, buf);

    return surface.?;
}

pub fn cairo_surface_transform_apply(image_surface: *c.cairo_surface_t, transform: WallpaperMode, width: u64, height: u64) !*c.cairo_surface_t {
    const surface = c.cairo_image_surface_create(c.CAIRO_FORMAT_ARGB32, @as(c_int, @intCast(width)), @as(c_int, @intCast(height))) orelse return error.cairoCreateImageSurfaceFailed;

    const cairo = c.cairo_create(surface) orelse return error.cairoCtxFailed;
    defer c.cairo_destroy(cairo);
    defer c.cairo_surface_destroy(image_surface);

    const image_width = @as(f64, @floatFromInt(c.cairo_image_surface_get_width(image_surface)));
    const image_height = @as(f64, @floatFromInt(c.cairo_image_surface_get_height(image_surface)));

    switch (transform) {
        .fit => {
            _ = c.cairo_rectangle(cairo, 0, 0, @as(f64, @floatFromInt(width)), @as(f64, @floatFromInt(height)));
            c.cairo_clip(cairo);
            const width_ratio: f64 = @as(f64, @floatFromInt(width)) / image_width;
            if (width_ratio * image_height >= @as(f64, @floatFromInt(height))) {
                c.cairo_scale(cairo, width_ratio, width_ratio);
            } else {
                const height_ratio = @as(f64, @floatFromInt(height)) / image_height;
                c.cairo_translate(cairo, @divFloor(-(image_width * height_ratio - @as(f64, @floatFromInt(width))), 2), 0);
                c.cairo_scale(cairo, height_ratio, height_ratio);
            }
        },
        .stretch => {
            c.cairo_scale(
                cairo,
                @as(f64, @floatFromInt(width)) / image_width,
                @as(f64, @floatFromInt(height)) / image_height,
            );
        },
    }
    c.cairo_set_source_surface(cairo, image_surface, 0, 0);
    c.cairo_paint(cairo);
    c.cairo_restore(cairo);

    c.cairo_surface_flush(surface);

    return surface;
}

pub fn cairo_buffer_create(self: *Self, width: c_int, height: c_int, stride: usize, data: [*c]u8) !void {
    const cairo_buffer_impl = wlr.Buffer.Impl{
        .destroy = cairo_handle_destroy,
        .get_dmabuf = undefined,
        .get_shm = undefined,
        .begin_data_ptr_access = cairo_data_access,
        .end_data_ptr_access = cairo_end_data_access,
    };

    self.base_buffer.init(&cairo_buffer_impl, width, height);

    self.data = data;
    self.stride = stride;
}

pub fn cairo_data_access(buffer: *wlr.Buffer, _: u32, data: **anyopaque, format: *u32, stride: *usize) callconv(.C) bool {
    const self = @fieldParentPtr(Self, "base_buffer", buffer);
    log.debug("Buffer data accessed", .{});

    data.* = self.data;
    stride.* = self.stride;
    format.* = c.DRM_FORMAT_ARGB8888;

    return true;
}
pub fn cairo_end_data_access(_: *wlr.Buffer) callconv(.C) void {
    log.debug("Buffer data access ended", .{});
}
pub fn cairo_handle_destroy(buffer: *wlr.Buffer) callconv(.C) void {
    const self = @fieldParentPtr(Self, "base_buffer", buffer);
    log.debug("Buffer destroyed", .{});

    if (!self.base_buffer.dropped) {
        self.base_buffer.drop();
    }
}
