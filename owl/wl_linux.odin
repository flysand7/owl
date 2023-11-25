//+private, +build linux
package owl

import "core:os"
import "core:log"

Wayland_State :: struct {
	display: i32,
}

Wayland_Window :: struct {
	
}

wl_try_init :: proc() -> bool {
	display, found := os.lookup_env("WAYLAND_DISPLAY", g.talloc)
	if !found {
		log.errorf("Wayland display not found.")
		return false
	}
	log.debugf("Wayland displays not supported yet.")
	return false
}

wl_terminate :: proc() {
	
}

wl_window_create :: proc(hints: ^Window_Hints) -> ^Window {
	return nil
}

wl_window_destroy :: proc(window: ^Window) {
	free(window)
}

wl_wait_event :: proc(timeout := DURATION_INDEFINITE) -> b32 {
	return false
}

wl_poll_events :: proc() -> bool {
	return false
}
