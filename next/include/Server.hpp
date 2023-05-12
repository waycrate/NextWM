#pragma once
#include "wlr.hpp"

class Server {
public:
	Server();
	~Server();

	wl_display *Display;
	wl_event_loop *EventLoop;
	wlr_backend *Backend;
	wlr_session *Session;
	wlr_renderer *Renderer;
	wlr_allocator *Allocator;
	wlr_compositor *Compositor;
	wlr_subcompositor *SubCompositor;
	wlr_drm *Drm;

	// Do we really need two?
	wlr_xdg_activation_v1 *XdgActivation;
	wlr_xdg_activation_v1 *Activation;

	wlr_output_layout *OutputLayout;
	wlr_idle *Idle;
	wlr_layer_shell_v1 *LayerShell;
	wlr_xdg_shell *XdgShell;
	wlr_cursor *Cursor;
	wlr_presentation *Presentation;
	wlr_scene *Scene;
	wlr_egl *Egl;
	int DrmFD;
	wlr_pointer_constraints_v1 *PointerConstraints;

	// All managers.
	wlr_relative_pointer_manager_v1 *RelativePointerManager;
	wlr_server_decoration_manager *ServerDecorationManager;
	wlr_xdg_decoration_manager_v1 *XdgDecorationManager;
	wlr_idle_inhibit_manager_v1 *IdleInhibitManager;
	wlr_pointer_gestures_v1 *PointerGestures;
	wlr_input_method_manager_v2 *InputMethodManager;
	wlr_text_input_manager_v3 *TextInputManager;
	wlr_session_lock_manager_v1 *SessionLockManager;
	wlr_drm_lease_v1_manager *DrmLeaseManager;
	wlr_xcursor_manager *XCursorManager;
	wlr_data_device_manager *DataDeviceManager;
	wlr_virtual_keyboard_manager_v1 *VirtualKeyboardManager;
	wlr_output_manager_v1 *OutputManager;
	wlr_output_power_manager_v1 *OutputPowerManager;
	wlr_input_inhibit_manager *InhibhitManager;
	wlr_keyboard_shortcuts_inhibit_manager_v1 *KeyboardShortcutInhibitManager;

	wlr_linux_dmabuf_v1 *LinuxDmaBuf;
	wlr_backend *HeadlessBackend;

	void initServer();
	void startServer();
	void deinit();

private:
	void initSignals();
	void initManagers();

	pid_t NextPID = 0;
};

inline std::unique_ptr<Server> NextServer;
