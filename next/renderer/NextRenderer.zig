// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/renderer/NextRenderer.zig
//
// Created by:	Aakash Sen Sharma, May 2023
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const std = @import("std");
const log = std.log.scoped(.NextRenderer);
const mem = std.mem;
const math = std.math;

const c = @import("../utils/c.zig");

const wlr = @import("wlroots");
const allocator = @import("../utils/allocator.zig").allocator;

const NextFrameBuffer = @import("NextFrameBuffer.zig");
const NextShader = @import("NextShader.zig");

const uint16_max = math.maxInt(u16);

pub const BlurShader = struct {
    program: c.GLuint = 0,
    proj: c.GLint = 0,
    tex: c.GLint = 0,
    pos_attrib: c.GLint = 0,
    tex_attrib: c.GLint = 0,
    radius: c.GLint = 0,
    halfpixel: c.GLint = 0,
    shader_src: []const u8,

    pub fn linkProgram(self: *BlurShader) anyerror!void {
        self.program = try NextShader.link_program(self.shader_src);

        self.proj = c.glGetUniformLocation(self.program, "proj");
        self.tex = c.glGetUniformLocation(self.program, "tex");
        self.radius = c.glGetUniformLocation(self.program, "radius");
        self.halfpixel = c.glGetUniformLocation(self.program, "halfpixel");
        self.pos_attrib = c.glGetAttribLocation(self.program, "pos");
        self.tex_attrib = c.glGetAttribLocation(self.program, "texcoord");
    }
};

// Framebuffer used by wlroots
//TODO: Figure out how to initialize this!
wlr_buffer: NextFrameBuffer = undefined,

main_buffer: NextFrameBuffer, // Main framebuffer used for rendering
blur_buffer: NextFrameBuffer, // Contains the blurred background for tiled windows.

viewport_width: i64 = 0,
viewport_height: i64 = 0,

projection: [9]f32 = undefined,

// Blur swaps between the two effect buffers everytime it scales the image.
effects_buffer: NextFrameBuffer, // Framebuffer used for effects
effects_buffer_swapped: NextFrameBuffer, // Swap framebuffer used for effects

shaders: struct {
    blur1: BlurShader,
    blur2: BlurShader,
},

blur_buffer_dirty: bool,
has_OES_egl_image_external: bool,
glEGLImageTargetTexture2DOES: c.PFNGLEGLIMAGETARGETTEXTURE2DOESPROC = undefined,

/// This function allocates memory to be free'd by the caller.
pub fn init(egl: *wlr.Renderer.wlr_egl) anyerror!*Self {
    const self = allocator.create(Self) catch {
        log.err("Failed to allocate NextRenderer!", .{});
        return error.NextRendererInitFailed;
    };
    errdefer allocator.destroy(self);

    // NOTE: This is probably going to be replaced with wlr_egl_make_current in wlroots 0.17.0
    if (c.eglMakeCurrent(wlr.Renderer.eglGetDisplay(egl), c.EGL_NO_SURFACE, c.EGL_NO_SURFACE, wlr.Renderer.eglGetContext(egl)) <= 0) {
        log.err("GLES2 RENDERER: Could not make EGL current", .{});
        return error.FailedToMakeEGLCurrent;
    }

    self.* = .{
        .main_buffer = NextFrameBuffer.create(),
        .blur_buffer = NextFrameBuffer.create(),
        .effects_buffer = NextFrameBuffer.create(),
        .effects_buffer_swapped = NextFrameBuffer.create(),
        .blur_buffer_dirty = true,
        .has_OES_egl_image_external = false,
        .shaders = .{
            .blur1 = .{ .shader_src = @embedFile("../shaders/blur1.frag") },
            .blur2 = .{ .shader_src = @embedFile("../shaders/blur2.frag") },
        },
    };

    log.info("Creating GLES2 NextRenderer.", .{});
    log.info("NextRenderer version: {s}", .{c.glGetString(c.GL_VERSION)});
    log.info("NextRenderer GL vendor: {s}", .{c.glGetString(c.GL_VENDOR)});
    log.info("NextRenderer GL renderer: {s}", .{c.glGetString(c.GL_RENDERER)});

    const extensions = c.glGetString(c.GL_EXTENSIONS);
    if (extensions) |ext| {
        log.info("Next Renderer supported GLES2 extensions: {s}\n", .{ext});

        if (mem.indexOf(u8, mem.span(ext), "GL_OES_EGL_image_external")) |_| {
            log.info("Found GL_OES_EGL_image_external!", .{});
            self.has_OES_egl_image_external = true;

            // Load gl proc
            const ptr = @ptrCast(?*const void, c.eglGetProcAddress("glEGLImageTargetTexture2DOES"));
            if (ptr) |proc| {
                // Don't ask me why.
                const proc_ptr = @ptrCast(**const void, &self.glEGLImageTargetTexture2DOES);
                proc_ptr.* = proc;
            } else {
                log.err("GLES2 Renderer: eglGetProcAddress(glEGLImageTargetTexture2DOES) failed", .{});
                return error.eglGetProcAddressFailed;
            }
        } else {
            log.info("Failed to find GL_OES_EGL_image_external!", .{});
        }
    } else {
        log.err("GLES2 Renderer: Failed to get GL_EXTENSIONS", .{});
        return error.getGlExtensionsFailed;
    }

    errdefer {
        c.glDeleteProgram(self.shaders.blur1.program);
        c.glDeleteProgram(self.shaders.blur2.program);
        if (c.eglMakeCurrent(wlr.Renderer.eglGetDisplay(egl), c.EGL_NO_SURFACE, c.EGL_NO_SURFACE, c.EGL_NO_CONTEXT) <= 0) {
            log.err("GLES2 Renderer: Could not unset current EGL", .{});
        }

        log.err("GLES2 Renderer: Error Initializing Shaders", .{});
    }

    //TODO: Link the other shader programs.
    try self.shaders.blur1.linkProgram();
    try self.shaders.blur2.linkProgram();

    if (c.eglMakeCurrent(wlr.Renderer.eglGetDisplay(egl), c.EGL_NO_SURFACE, c.EGL_NO_SURFACE, c.EGL_NO_CONTEXT) <= 0) {
        log.err("GLES2 Renderer: Could not unset current EGL", .{});
        return error.EGLCurrentUnsetFailed;
    } else {
        log.info("GLES2 Renderer: Shaders Initialized Successfully!", .{});
    }

    return self;
}

pub fn destroy(self: *Self) void {
    self.main_buffer.release();
    self.blur_buffer.release();
    allocator.destroy(self);
}

pub fn begin(self: *Self, width: i32, height: i32) !void {
    c.glViewport(0, 0, width, height);

    self.viewport_width = width;
    self.viewport_height = height;

    var wlr_fb: c.GLint = uint16_max;
    c.glGetIntegerv(c.GL_FRAMEBUFFER_BINDING, &wlr_fb);

    if (wlr_fb < 0) {
        log.err("Failed to get wlr framebuffer!", .{});
        std.c.abort();
    }

    self.wlr_buffer.fb = @intCast(c_uint, wlr_fb);

    try self.main_buffer.update(width, height);
    try self.effects_buffer.update(width, height);
    try self.effects_buffer_swapped.update(width, height);

    // Add a stencil buffer to the main buffer and bind the main buffer.
    self.main_buffer.bind();
    try self.main_buffer.addStencilBuffer(width, height);

    //TODO: Refresh projection matrix.
    self.matrix_projection();
    c.glBlendFunc(c.GL_ONE, c.GL_ONE_MINUS_SRC_ALPHA);

    // Bind to our main framebuffer
    self.main_buffer.bind();
}

//TODO: Finish matrix projection.
fn matrix_projection(self: *Self) void {
    mem.set(f32, &self.projection, 0);
}
