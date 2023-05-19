#include <iterator>
#include <vector>
#include <string>
#include <filesystem>
#include <stdexcept>

extern "C" {
#include <sys/resource.h>
}

#include "wlr.hpp"
#include "Server.hpp"

static void increase_nofile_limit(void) {
	static struct rlimit nofile_rlimit;

	nofile_rlimit.rlim_max = 0;
	nofile_rlimit.rlim_cur = 0;

	if (getrlimit(RLIMIT_NOFILE, &nofile_rlimit) != 0) {
		goto label;
	}

	nofile_rlimit.rlim_cur = nofile_rlimit.rlim_max;
	if (setrlimit(RLIMIT_NOFILE, &nofile_rlimit) != 0) {
		goto label;
	}

	std::cout << "Successfuly bumped open files limit to rlim_max!" << std::endl;
	return;

label:
	std::cout << "Failed to bump max open files limit" << std::endl;
	return;
}

int main(int argc, char **argv) {
	if (!getenv("XDG_RUNTIME_DIR"))
		throw std::runtime_error("XDG_RUNTIME_DIR is not set!");

	increase_nofile_limit();

	// Setting important wayland environment variables.
	setenv("MOZ_ENABLE_WAYLAND", "1", 1);
	setenv("XDG_BACKEND", "wayland", 1);
	setenv("XDG_CURRENT_DESKTOP", "NextWM", 1);
	setenv("XDG_SESSION_TYPE", "wayland", 1);
	setenv("_JAVA_AWT_WM_NONREPARENTING", "1", 1);

	std::cout << "Welcome to NextWM" << std::endl;

	// TODO: Init NextWM Tree.

	// Initializing wlroots logging
	wlr_log_init(WLR_DEBUG, nullptr);

	NextServer = std::make_unique<Server>();
	NextServer->initServer();

	//TODO: Log, init finished;
	NextServer->startServer();

	//TODO: Log, lifecycle of server ended.
	if (NextServer->Display) {
		NextServer->deinit();
	}

	return EXIT_SUCCESS;
}
