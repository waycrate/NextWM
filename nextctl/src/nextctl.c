/* SPDX-License-Identifier: BSD 2-Clause "Simplified" License
 *
 * nextctl/nextctl.c
 *
 * Created by:	Aakash Sen Sharma, May 2022
 * Copyright:	(C) 2022, Aakash Sen Sharma & Contributors
 */

#include "nextctl.h"

int main(int argc, char *argv[]) {
	for (int i = 0; i < argc; i++) {
		if (strcmp("-h", argv[i]) == 0 || strcmp("--help", argv[i]) == 0) {
			(void)fputs(usage, stderr);
			return EXIT_SUCCESS;
		} else if (strcmp("-v", argv[i]) == 0 || strcmp("--version", argv[i]) == 0) {
			(void)printf("Nextctl version: %s\n", VERSION);
			return EXIT_SUCCESS;
		}
	}

	struct nextctl_state state = { 0 };
	state.wl_display = wl_display_connect(NULL);

	if (state.wl_display == NULL) {
		(void)fputs("ERROR: Cannot connect to wayland display.\n", stderr);
		return EXIT_FAILURE;
	}

	state.wl_registry = wl_display_get_registry(state.wl_display);
	(void)wl_registry_add_listener(state.wl_registry, &registry_listener, &state);

	if (wl_display_dispatch(state.wl_display) < 0) {
		(void)fputs("ERROR: wayland dispatch failed.\n", stderr);
		return EXIT_FAILURE;
	}

	if (state.next_control == NULL) {
		(void)fputs("ERROR: Compositor doesn't implement NextControlV1.\n", stderr);
		return EXIT_FAILURE;
	}

	for (int i = 1; i < argc; i++) {
		(void)next_control_v1_add_argument(state.next_control, argv[i]);
	}

	state.next_command_callback = next_control_v1_run_command(state.next_control);
	(void)next_command_callback_v1_add_listener(state.next_command_callback,
												&callback_listener, NULL);

	if (wl_display_dispatch(state.wl_display) < 0) {
		(void)fputs("ERROR: wayland dispatch failed.\n", stderr);
		return EXIT_FAILURE;
	}

	return EXIT_SUCCESS;
}

static void registry_handle_global(void *data, struct wl_registry *registry,
								   uint32_t name, const char *interface,
								   uint32_t version) {
	struct nextctl_state *state = data;

	if (strcmp(interface, next_control_v1_interface.name) == 0) {
		state->next_control =
			wl_registry_bind(registry, name, &next_control_v1_interface, 1);
	}
}

static void next_handle_success(void *data, struct next_command_callback_v1 *callback,
								const char *output) {
	(void)fputs(output, stdout);
}

static void next_handle_failure(void *data, struct next_command_callback_v1 *callback,
								const char *failure_message) {
	(void)fprintf(stderr, "ERROR: %s", failure_message);
	if (strcmp("Unknown command\n\0", failure_message) == 0 ||
		strcmp("No command provided\n\0", failure_message) == 0) {
		(void)fputs(usage, stderr);
	}
}
