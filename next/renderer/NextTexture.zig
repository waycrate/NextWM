// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/renderer/NextTexture.zig
//
// Created by:	Aakash Sen Sharma, May 2023
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const Self = @This();

const c = @import("../utils/c.zig");

target: c.GLuint,
id: c.GLuint,
has_alpha: bool,
width: i32,
height: i32,
