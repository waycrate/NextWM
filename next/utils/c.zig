// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/utils/c.zig
//
// Created by:	Aakash Sen Sharma, May 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

pub usingnamespace @cImport({
    @cDefine("_POSIX_C_SOURCE", "200809L");
    @cInclude("stdlib.h");
    @cInclude("sys/stat.h");
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
    @cInclude("libinput.h");
    @cInclude("cairo.h");
    @cInclude("stdio.h"); // Required by jpeglib.h
    @cInclude("jpeglib.h");
    @cInclude("drm_fourcc.h");
});
