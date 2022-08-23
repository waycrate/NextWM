// SPDX-License-Identifier: BSD 2-Clause "Simplified" License
//
// next/utils/wlr_log.c
//
// Created by:	Aakash Sen Sharma, August 2022
// Copyright:	(C) 2022, Aakash Sen Sharma & Contributors

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

#include <wlr/util/log.h>

#define BUFFER_SIZE 1024

void wlr_log_callback(enum wlr_log_importance importance, const char *ptr, size_t len);
static void callback(enum wlr_log_importance importance, const char *fmt, va_list args) {
	char buffer[BUFFER_SIZE];

	va_list args_copy;
	va_copy(args_copy, args);

	const int length = vsnprintf(buffer, BUFFER_SIZE, fmt, args);

	if (length + 1 <= BUFFER_SIZE) {
		wlr_log_callback(importance, buffer, length);
	} else {
		char *allocated_buffer = malloc(length + 1);
		if (allocated_buffer != NULL) {
			const int length2 = vsnprintf(allocated_buffer, length + 1, fmt, args_copy);
			assert(length2 == length);
			wlr_log_callback(importance, allocated_buffer, length);
			free(allocated_buffer);
		}
	}

	va_end(args_copy);
}

void wlr_fmt_log(enum wlr_log_importance importance) {
	wlr_log_init(importance, callback);
}
