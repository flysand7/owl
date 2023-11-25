//+private, +build linux
package owl

import "core:os"
import "core:mem"
import "core:log"
import "core:runtime"

import "vendor:x11/xlib"

// Read-only global state. Initialized once during the library initialization.
g: Global_State

OS_Window :: struct {
	x11: X11_Window,
	wl:  Wayland_Window,
}

Global_State :: struct {
	wm:      Window_Manager,
	palloc:  mem.Allocator,
	talloc:  mem.Allocator,
	log:     log.Logger,
	x11:     X11_State,
	wl:      Wayland_State,
	windows: [dynamic]^Window,
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
	// Initialize the windows dynamic array
	allocation_err: mem.Allocator_Error
	g.windows, allocation_err = make_dynamic_array([dynamic]^Window, g.palloc)
	if allocation_err != nil {
		log.fatalf("Failed to allocate the array for windows: %v", allocation_err)
		return nil
	}
	return nil
}

os_terminate :: proc() {
	context.logger = g.log
	if g.wm == .Wayland {
		for window in g.windows {
			wl_window_destroy(window)
			free(window)
		}
		delete(g.windows)
		wl_terminate()
	} else if g.wm == .X11 {
		for window in g.windows {
			x11_window_destroy(window)
			free(window)
		}
		delete(g.windows)
		x11_terminate()
	} else {
		panic("No window manager")
	}
}

os_window_create :: proc(hints: ^Window_Hints) -> ^Window {
	context.logger = g.log
	window: ^Window = nil
	if g.wm == .Wayland {
		window = wl_window_create(hints)
	} else if g.wm == .X11 {
		window = x11_window_create(hints)
	} else {
		panic("No window manager")
	}
	if window != nil {
		append(&g.windows, window)
	}
	return window
}

os_window_destroy :: proc(window: ^Window) {
	context.logger = g.log
	if g.wm == .Wayland {
		wl_window_destroy(window)
	} else if g.wm == .X11 {
		x11_window_destroy(window)
	} else {
		panic("No window manager")
	}
	window_index := -1
	for our_window, index in g.windows {
		if window == our_window {
			window_index = index
			break
		}
	}
	assert(window_index >= 0, "Destroying non-existent window")
	unordered_remove(&g.windows, window_index)
}

os_wait_event :: proc(timeout := DURATION_INDEFINITE) -> b32 {
	context.logger = g.log
	if g.wm == .Wayland {
		return wl_wait_event(timeout)
	} else if g.wm == .X11 {
		return x11_wait_event(timeout)
	}
	panic("No window manager")
}

os_poll_events :: proc() -> bool {
	context.logger = g.log
	if g.wm == .Wayland {
		return wl_poll_events()
	} else if g.wm == .X11 {
		return x11_poll_events()
	}
	panic("No window manager")	
}
