// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/utils/c.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

pub usingnamespace @cImport({
    @cDefine("_POSIX_C_SOURCE", "200809L");
    @cInclude("stdlib.h");
    @cInclude("unistd.h");
    @cInclude("EGL/egl.h");
    @cInclude("GLES3/gl3.h");
    @cInclude("GLES3/gl3ext.h");
    @cInclude("GLES2/gl2ext.h");
});
