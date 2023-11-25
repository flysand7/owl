//+private, +build linux
package owl

import "core:os"
import "core:log"

Wayland_State :: struct {
	display: i32,
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
