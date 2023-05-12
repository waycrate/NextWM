#include "Server.hpp"

int handleTermSignal(int signal, void *data) {
	//TODO: Log that we're stopping here.
	if (signal == SIGTERM || signal == SIGINT || signal == SIGKILL) {
		NextServer->deinit();
	}

	return 0;
}

Server::Server() {
	NextPID = getpid();
}

Server::~Server() {
	deinit();
}

void Server::deinit() {
}

void Server::initServer() {
	Display = wl_display_create();
	EventLoop = wl_display_get_event_loop(Display);

	wl_event_loop_add_signal(EventLoop, SIGTERM, handleTermSignal, nullptr);

	wlr_log_init(WLR_INFO, nullptr);

	Backend = wlr_backend_autocreate(Display, &Session);
	if (!Backend) {
		throw std::runtime_error("wlr_backend_autocreate() failed!");
	}

	DrmFD = wlr_backend_get_drm_fd(Backend);
	if (DrmFD < 0) {
		//TODO: log
		throw std::runtime_error("wlr_backend_get_drm_fd() failed!");
	}

	Renderer = wlr_gles2_renderer_create_with_drm_fd(DrmFD);
	if (!Renderer) {
		//TODO: log
		throw std::runtime_error("wlr_gles2_renderer_create_with_drm_fd() failed!");
	}

	wlr_renderer_init_wl_shm(Renderer, Display);

	if (wlr_renderer_get_dmabuf_texture_formats(Renderer)) {
		if (wlr_renderer_get_drm_fd(Renderer) >= 0)
			wlr_drm_create(Display, Renderer);

		LinuxDmaBuf = wlr_linux_dmabuf_v1_create_with_renderer(Display, 4, Renderer);
	}

	Allocator = wlr_allocator_autocreate(Backend, Renderer);

	if (!Allocator) {
		//TOOD: log
		throw std::runtime_error("wlr_allocator_autocreate() failed!");
	}

	Egl = wlr_gles2_renderer_get_egl(Renderer);
	if (!Egl) {
		//TODO: log
		throw std::runtime_error("wlr_gles2_renderer_get_egl() egl");
	}

	Compositor = wlr_compositor_create(Display, 6, Renderer);
	SubCompositor = wlr_subcompositor_create(Display);
	DataDeviceManager = wlr_data_device_manager_create(Display);

	wlr_export_dmabuf_manager_v1_create(Display);
	wlr_data_control_manager_v1_create(Display);
	wlr_gamma_control_manager_v1_create(Display);
	wlr_primary_selection_v1_device_manager_create(Display);
	wlr_viewporter_create(Display);

	OutputLayout = wlr_output_layout_create();
	OutputPowerManager = wlr_output_power_manager_v1_create(Display);

	Scene = wlr_scene_create();
	wlr_scene_attach_output_layout(Scene, OutputLayout);

	XdgShell = wlr_xdg_shell_create(Display, 5);

	Cursor = wlr_cursor_create();
	wlr_cursor_attach_output_layout(Cursor, OutputLayout);

	if (const auto X_CURSOR_ENV = getenv("XCURSOR_SIZE");
		!X_CURSOR_ENV || std::string(X_CURSOR_ENV).empty())
		setenv("XCURSOR_SIZE", "24", true);

	const auto X_CURSOR_ENV = getenv("XCURSOR_SIZE");
	uint32_t cursorSize = 24;

	try {
		cursorSize = std::stoi(X_CURSOR_ENV);
	} catch (std::exception &e) {
		//TODO: Log that Xcursror is invalid
	}

	XCursorManager = wlr_xcursor_manager_create(nullptr, cursorSize);
	wlr_xcursor_manager_load(XCursorManager, 1);

	//TODO: Seat init

	Presentation = wlr_presentation_create(Display, Backend);
	LayerShell = wlr_layer_shell_v1_create(Display, 4);
	ServerDecorationManager = wlr_server_decoration_manager_create(Display);
}

void Server::startServer() {
	//TODO: Initialize all the signals;
	auto socket = wl_display_add_socket_auto(Display);
	if (!socket) {
		throw std::runtime_error("Failed to add wayland socket");
	}

	setenv("WAYLAND_DISPLAY", socket, 1);

	// Ignore sigpipe from wlroots.
	signal(SIGPIPE, SIG_IGN);

	//TODO: Log which wayland socket we are running on.
	if (!wlr_backend_start(Backend)) {
		//TODO: Backend didn't start.
		wlr_backend_destroy(Backend);
		wl_display_destroy(Display);
		throw std::runtime_error("The backend couldn't start.");
	}

	wlr_xcursor_manager_set_cursor_image(XCursorManager, "left_ptr", Cursor);

	wl_display_run(Display);
}
