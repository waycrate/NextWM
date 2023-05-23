// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/renderer/NextShader.zig
//
// Created by:	Aakash Sen Sharma, May 2023
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const std = @import("std");
const log = std.log.scoped(.NextShader);
const c = @import("../utils/c.zig");

program: c.GLuint,

pub const glShaderType = enum(c_uint) {
    VertexShader = c.GL_VERTEX_SHADER,
    FragmentShader = c.GL_FRAGMENT_SHADER,
};

pub fn link_program(shader_src: []const u8) anyerror!c.GLuint {
    const common_vertex_shader = try compile_shader(.VertexShader, @embedFile("../shaders/common.vert"));
    const fragment_shader = try compile_shader(.FragmentShader, shader_src);

    const program = c.glCreateProgram();
    c.glAttachShader(program, common_vertex_shader);
    c.glAttachShader(program, fragment_shader);

    c.glLinkProgram(program);

    c.glDetachShader(program, common_vertex_shader);
    c.glDetachShader(program, fragment_shader);
    c.glDeleteShader(common_vertex_shader);
    c.glDeleteShader(fragment_shader);

    var status: c.GLint = undefined;
    c.glGetProgramiv(program, c.GL_LINK_STATUS, &status);
    if (status == c.GL_FALSE) {
        log.err("Failed to link shader!", .{});
        return error.GlLinkShaderFailed;
    } else if (status == c.GL_TRUE) {
        log.info("Successfully linked shader to program!", .{});
    }

    return program;
}

fn compile_shader(shader_type: glShaderType, shader_src: []const u8) anyerror!c.GLuint {
    const shader = c.glCreateShader(@enumToInt(shader_type));

    const source_len = @intCast(c_int, shader_src.len);
    c.glShaderSource(shader, 1, &shader_src.ptr, &source_len);
    c.glCompileShader(shader);

    var status: c.GLint = undefined;
    c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &status);
    if (status == c.GL_FALSE) {
        log.err("Failed to compile shader!", .{});
        return error.GlShaderCompileFailed;
    } else if (status == c.GL_TRUE) {
        log.info("Successfully compiled {s}:\n {s}", .{ @tagName(shader_type), shader_src });
    }

    return shader;
}
