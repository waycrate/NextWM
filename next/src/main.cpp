#include <iostream>
#include <iterator>
#include <vector>
#include <string>
#include <filesystem>
#include <stdexcept>

#include "wlr.hpp"
#include "Server.hpp"

int main(int argc, char **argv) {
	if (!getenv("XDG_RUNTIME_DIR"))
		throw std::runtime_error("XDG_RUNTIME_DIR is not set!");

	setenv("MOZ_ENABLE_WAYLAND", "1", 1);
	setenv("XDG_BACKEND", "wayland", 1);
	setenv("XDG_CURRENT_DESKTOP", "NextWM", 1);
	setenv("XDG_SESSION_TYPE", "wayland", 1);
	setenv("_JAVA_AWT_WM_NONREPARENTING", "1", 1);

	std::cout << "Welcome to NextWM" << std::endl;

	NextServer = std::make_unique<Server>();
	NextServer->initServer();

	//TODO: Log, init finished;

	NextServer->startServer();
	//TODO: Log, lifecycle of server ended.

	if (NextServer->Display) {
		wl_display_destroy_clients(NextServer->Display);
		wl_display_destroy(NextServer->Display);
	}

	return EXIT_SUCCESS;
}
