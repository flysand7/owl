//+private, +build linux
package owl

import "core:os"
import "core:mem"
import "core:log"
import "core:runtime"

import "vendor:x11/xlib"

// Read-only global state. Initialized once during the library initialization.
g: Global_State

Global_State :: struct {
	wm:     Window_Manager,
	palloc: mem.Allocator,
	talloc: mem.Allocator,
	log:    log.Logger,
	x11:    X11_State,
	wl:     Wayland_State,
}

Window_Manager :: enum {
	None,
	X11,
	Wayland,
}

os_init :: proc(
	hints: Init_Hints,
	logger: log.Logger,
	perm_alloc: mem.Allocator,
	temp_alloc: mem.Allocator,
	loc: runtime.Source_Code_Location,
) -> Error {
	// Set the memory allocators for the library.
	g.palloc = perm_alloc
	g.talloc = temp_alloc
	perm_alloc_features : mem.Allocator_Mode_Set = mem.query_features(perm_alloc)
	if .Free not_in perm_alloc_features {
		panic("The provided permanent allocator does not implement .Free mode", loc)
	}
	if .Resize not_in perm_alloc_features {
		panic("The provided permanent allocator does not implement .Resize mode", loc)
	}
	// Initialize the logger.
	if .Logger in hints {
		g.log = logger
	} else {
		g.log = log.nil_logger()
	}
	// Check if the window manager is present, and if so, which one, and initialize it.
	window_manager := Window_Manager.None
	if wl_try_init() {
		window_manager = .Wayland
	} else if x11_try_init() {
		window_manager = .X11
	}
	if window_manager == .None {
		return .No_Window_Manager
	}
	g.wm = window_manager
	return nil
}

os_terminate :: proc() {
	if g.wm == .Wayland {
		wl_terminate()
	} else if g.wm == .X11 {
		x11_terminate()
	}
}
