// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// src/utils/allocator.zig
//
// Created by:	Aakash Sen Sharma, July 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

const std = @import("std");

// Global allocator to be used across the project.
pub const allocator = std.heap.c_allocator;
