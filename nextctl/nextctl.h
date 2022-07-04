/* SPDX-License-Identifier: BSD 2-Clause "Simplified" License
 *
 * nextctl/nextctl.h
 *
 * Created by:	Aakash Sen Sharma, May 2022
 * Copyright:	(C) 2022, Aakash Sen Sharma & Contributors
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>

#include "next-control-v1.h"

const char usage[] = "Usage: nextctl <command>\n"
                     "  -h, --help      Print this help message and exit.\n\n"
                     "Complete documentation for recognized commands can be found in\n"
                     "the nextctl(1) man page.\n";

static void noop(){}
static void registry_handle_global(void *, struct wl_registry *, uint32_t, const char *, uint32_t);
static void next_handle_success(void *, struct next_command_callback_v1 *, const char *);
static void next_handle_failure(void *, struct next_command_callback_v1 *, const char *);

struct nextctl_state {
  struct wl_display                 *wl_display;
  struct wl_registry                *wl_registry;
  struct next_control_v1            *next_control;
  struct next_command_callback_v1   *next_command_callback;
};

static const struct wl_registry_listener registry_listener = {
    .global         = registry_handle_global,
    .global_remove  = noop,
};

static const struct next_command_callback_v1_listener callback_listener = {
    .success = next_handle_success,
    .failure = next_handle_failure,
};

