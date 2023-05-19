#include "Server.hpp"
#define XWAYLAND_IS_LAZY true

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
	//Destroy root
	wlr_xwayland_destroy(Xwayland);
	wl_display_destroy_clients(Display);
	wl_display_destroy(Display);
}

void Server::initServer() {
	Display = wl_display_create();
	EventLoop = wl_display_get_event_loop(Display);

	wl_event_loop_add_signal(EventLoop, SIGTERM, handleTermSignal, nullptr);

	Backend = wlr_backend_autocreate(Display);
	if (!Backend) {
		throw std::runtime_error("wlr_backend_autocreate() failed!");
	}

	Renderer = wlr_renderer_autocreate(Backend);
	if (!Renderer) {
		throw std::runtime_error("wlr_renderer_autocreate() failed!");
	}

	if (!wlr_renderer_init_wl_display(Renderer, Display)) {
		throw std::runtime_error("wlr_renderer_init_wl_display() failed!");
	}

	if (wlr_renderer_get_dmabuf_texture_formats(Renderer) != nullptr) {
		if (wlr_renderer_get_drm_fd(Renderer) >= 0) {
			wlr_drm_create(Display, Renderer);
			LinuxDmaBuf = wlr_linux_dmabuf_v1_create(Display, Renderer);
		}
	}

	Allocator = wlr_allocator_autocreate(Backend, Renderer);
	if (!Allocator) {
		throw std::runtime_error("wlr_allocator_autocreate() failed!");
	}

	Compositor = wlr_compositor_create(Display, Renderer);
	DataDeviceManager = wlr_data_device_manager_create(Display);

	wlr_data_control_manager_v1_create(Display);
	wlr_export_dmabuf_manager_v1_create(Display);
	wlr_gamma_control_manager_v1_create(Display);
	wlr_primary_selection_v1_device_manager_create(Display);
	wlr_screencopy_manager_v1_create(Display);
	wlr_single_pixel_buffer_manager_v1_create(Display);
	wlr_subcompositor_create(Display);
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
		cursorSize = (uint32_t)std::stoi(X_CURSOR_ENV);
	} catch (std::exception &e) {
		//TODO: Log that Xcursror is invalid
	}

	XCursorManager = wlr_xcursor_manager_create(nullptr, cursorSize);
	wlr_xcursor_manager_load(XCursorManager, 1);

	//TODO: Seat init

	Presentation = wlr_presentation_create(Display, Backend);
	LayerShell = wlr_layer_shell_v1_create(Display);
	ServerDecorationManager = wlr_server_decoration_manager_create(Display);
	wlr_server_decoration_manager_set_default_mode(
		ServerDecorationManager, WLR_SERVER_DECORATION_MANAGER_MODE_SERVER);

	//TODO: Idle create
	wlr_xdg_output_manager_v1_create(Display, OutputLayout);
	OutputManager = wlr_output_manager_v1_create(Display);

	InhibhitManager = wlr_input_inhibit_manager_create(Display);
	KeyboardShortcutInhibitManager = wlr_keyboard_shortcuts_inhibit_v1_create(Display);
	PointerConstraints = wlr_pointer_constraints_v1_create(Display);

	VirtualKeyboardManager = wlr_virtual_keyboard_manager_v1_create(Display);
	VirtualPointerManager = wlr_virtual_pointer_manager_v1_create(Display);

	ForeignToplevelManager = wlr_foreign_toplevel_manager_v1_create(Display);
	DrmLeaseManager = wlr_drm_lease_v1_manager_create(Display, Backend);
	if (!DrmLeaseManager) {
		std::cout << "Failed to create wlr_drm_lease_device_v1." << std::endl
				  << "VR will be unavailable." << std::endl;
	}

	XdgForeignRegistry = wlr_xdg_foreign_registry_create(Display);

	wlr_xdg_foreign_v1_create(Display, XdgForeignRegistry);
	wlr_xdg_foreign_v2_create(Display, XdgForeignRegistry);

	//TODO: Tablet manager.
	IdleInhibitManager = wlr_idle_inhibit_v1_create(Display);
	InputMethodManager = wlr_input_method_manager_v2_create(Display);
	PointerGestures = wlr_pointer_gestures_v1_create(Display);
	TextInputManager = wlr_text_input_manager_v3_create(Display);

	HeadlessBackend = wlr_headless_backend_create(Display);
	if (!HeadlessBackend) {
		//TODO: log
		throw std::runtime_error("Failed to create secondary headless backend");
	}

	SessionLockManager = wlr_session_lock_manager_v1_create(Display);
	wlr_multi_backend_add(Backend, HeadlessBackend);
	struct wlr_output *headless_wlr_output =
		wlr_headless_add_output(HeadlessBackend, 800, 600);
	wlr_output_set_name(headless_wlr_output, "Fallback");

	initManagers();
}

void Server::startServer() {
	Xwayland = wlr_xwayland_create(Display, Compositor, XWAYLAND_IS_LAZY);
	if (!Xwayland) {
		std::cout << "Failed to start Xwayland" << std::endl;
		unsetenv("DISPLAY");
	} else {
		setenv("DISPLAY", Xwayland->display_name, true);
	}

	initSignals();

	auto socket = wl_display_add_socket_auto(Display);
	if (!socket) {
		throw std::runtime_error("Failed to add wayland socket");
	}
	std::cout << "Running NextWM on socket: " << socket << std::endl;

	setenv("WAYLAND_DISPLAY", socket, 1);

	// Ignore sigpipe from wlroots.
	signal(SIGPIPE, SIG_IGN);

	//TODO: Log which wayland socket we are running on.
	if (!wlr_backend_start(Backend)) {
		wlr_backend_destroy(Backend);
		wl_display_destroy(Display);
		throw std::runtime_error("wlr_backend_start() failed!");
	}

	wl_display_run(Display);
}

void Server::initSignals() {
}

void Server::initManagers() {
}
