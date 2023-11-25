//+private, +build linux
package owl

import "core:os"
import "core:mem"
import "core:log"
import "core:runtime"

import "vendor:x11/xlib"

OS_Window :: struct {
	x11: X11_Window,
	wl:  Wayland_Window,
}

OS_Global_State :: struct {
	wm:      Window_Manager,
	x11:     X11_State,
	wl:      Wayland_State,
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
	} else {
		panic("No window manager")
	}
}

os_window_create :: proc(hints: ^Window_Hints) -> ^Window {
	if g.wm == .Wayland {
		return wl_window_create(hints)
	} else if g.wm == .X11 {
		return x11_window_create(hints)
	} else {
		panic("No window manager")
	}
}

os_window_destroy :: proc(window: ^Window) {
	if g.wm == .Wayland {
		wl_window_destroy(window)
	} else if g.wm == .X11 {
		x11_window_destroy(window)
	} else {
		panic("No window manager")
	}
}

os_wait_event :: proc(timeout := DURATION_INDEFINITE) -> b32 {
	if g.wm == .Wayland {
		return wl_wait_event(timeout)
	} else if g.wm == .X11 {
		return x11_wait_event(timeout)
	}
	panic("No window manager")
}

os_poll_events :: proc() -> bool {
	if g.wm == .Wayland {
		return wl_poll_events()
	} else if g.wm == .X11 {
		return x11_poll_events()
	}
	panic("No window manager")	
}
