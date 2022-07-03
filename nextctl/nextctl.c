#include "next-control-v1.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>

struct nextctl_state {
  struct wl_display      *wl_display;
  struct wl_registry     *wl_registry;
  struct wl_seat         *wl_seat;
  struct next_control_v1 *next_control;
};

static void noop() {}

static void registry_handle_global(void *data, struct wl_registry *registry,
                                   uint32_t name, const char *interface,
                                   uint32_t version) {
  struct nextctl_state *state = data;
  if (strcmp(interface, next_control_v1_interface.name) == 0) {
    state->next_control =
        wl_registry_bind(registry, name, &next_control_v1_interface, 1);
  } else if (strcmp(interface, wl_seat_interface.name) == 0) {
    state->wl_seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
  }
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_handle_global,
    .global_remove = noop,
};

int main(int argc, char *argv[]) {
  struct nextctl_state state = {0};
  state.wl_display = wl_display_connect(NULL);
  if (state.wl_display == NULL) {
    fputs("ERROR: Cannot connect to wayland display.\n", stderr);
    return EXIT_FAILURE;
  }

  state.wl_registry = wl_display_get_registry(state.wl_display);
  wl_registry_add_listener(state.wl_registry, &registry_listener, &state);

  if (wl_display_dispatch(state.wl_display) < 0) {
    fputs("ERROR: wayland dispatch failed.\n", stderr);
    return EXIT_FAILURE;
  }
  if (state.next_control == NULL) {
    fputs("ERROR: Compositor doesn't implement next_control_v1.\n", stderr);
  }
  if (state.wl_seat == NULL) {
    fputs("ERROR: Compositor doesn't implement wl_seat.\n", stderr);
  }
  return EXIT_SUCCESS;
}
