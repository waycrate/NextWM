// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/renderer/NextFrameBuffer.zig
//
// Created by:	Aakash Sen Sharma, May 2023
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const std = @import("std");
const math = std.math;

const NextTexture = @import("NextTexture.zig");

const log = std.log.scoped(.NextFrameBuffer);
const c = @import("../utils/c.zig");

// Used for OpenGL debugging as a known value.
const uint16_max = math.maxInt(u16);

next_texture: NextTexture,
fb: c.GLuint,
stencil_buffer: c.GLuint,

pub fn create() Self {
    return .{
        .fb = uint16_max,
        .stencil_buffer = uint16_max,
        .next_texture = .{
            .id = 0,
            .target = 0,
            .width = uint16_max,
            .height = uint16_max,
            .has_alpha = false,
        },
    };
}

pub fn release(self: *Self) void {
    log.debug("Releasing FrameBuffer!", .{});
    if (self.fb != uint16_max and self.fb > 0) {
        c.glDeleteFramebuffers(1, &self.fb);
    }
    self.fb = uint16_max;

    log.debug("Releasing StencilBuffer!", .{});
    if (self.stencil_buffer != uint16_max and self.stencil_buffer > 0) {
        c.glDeleteRenderbuffers(1, &self.stencil_buffer);
    }
    self.stencil_buffer = uint16_max;

    log.debug("Releasing NextTexture!", .{});
    if (self.next_texture.id > 0) {
        c.glDeleteTextures(1, &self.next_texture.id);
    }
    self.next_texture.id = 0;
    self.next_texture.width = uint16_max;
    self.next_texture.height = uint16_max;
}

pub fn bind(self: *Self) void {
    c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.fb);
}

pub fn addStencilBuffer(self: *Self, width: i32, height: i32) !void {
    if (self.stencil_buffer == uint16_max) {
        c.glGenRenderbuffers(1, &self.stencil_buffer);
        c.glBindRenderbuffer(c.GL_RENDERBUFFER, self.stencil_buffer);
        c.glRenderbufferStorage(c.GL_RENDERBUFFER, c.GL_STENCIL_INDEX8, width, height);
        c.glFramebufferRenderbuffer(c.GL_FRAMEBUFFER, c.GL_STENCIL_ATTACHMENT, c.GL_RENDERBUFFER, self.stencil_buffer);

        var status: c.GLenum = c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER);
        if (status != c.GL_FRAMEBUFFER_COMPLETE) {
            log.err("Stencil buffer incomplete, couldn't create! (FB status: {d})", .{status});
            return;
        }

        log.debug("Stencil buffer created, status {d}", .{status});
    }
}

pub fn update(self: *Self, width: i32, height: i32) !void {
    var first_alloc = false;

    if (self.fb == uint16_max) {
        c.glGenFramebuffers(1, &self.fb);
        first_alloc = true;
    }

    if (self.next_texture.id == 0) {
        first_alloc = true;
        c.glGenTextures(1, &self.next_texture.id);
        c.glBindTexture(c.GL_TEXTURE_2D, self.next_texture.id);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, c.GL_CLAMP_TO_EDGE);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
    }

    if (first_alloc or self.next_texture.width != width or self.next_texture.height != height) {
        c.glBindTexture(c.GL_TEXTURE_2D, self.next_texture.id);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA, width, height, 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, null);

        c.glBindFramebuffer(c.GL_FRAMEBUFFER, self.fb);
        c.glFramebufferTexture2D(c.GL_FRAMEBUFFER, c.GL_COLOR_ATTACHMENT0, c.GL_TEXTURE_2D, self.next_texture.id, 0);

        self.next_texture.target = c.GL_TEXTURE_2D;
        self.next_texture.has_alpha = false;
        self.next_texture.width = width;
        self.next_texture.width = height;

        const status = c.glCheckFramebufferStatus(c.GL_FRAMEBUFFER);

        if (status != c.GL_FRAMEBUFFER_COMPLETE) {
            log.err("Framebuffer incomplete, couldn't create (FB status: {d})", .{status});
            return error.FrameBufferIncomplete;
        }

        log.info("Framebuffer created, status: {d}", .{status});
    }

    c.glBindTexture(c.GL_TEXTURE_2D, 0);
}
