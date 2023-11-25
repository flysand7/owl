//+private, +build linux
package owl

import "core:os"
import "core:log"
import "core:dynlib"
import "core:strings"

import "vendor:x11/xlib"

X11_State :: struct {
	library:        dynlib.Library,
	display:        ^xlib.Display,
	// X11 atoms.
	wm_delete:      xlib.Atom,
	// X11 procedures.
	XOpenDisplay:   type_of(xlib.XOpenDisplay),
	XCloseDisplay:  type_of(xlib.XCloseDisplay),
	XCreateWindow:  type_of(xlib.XCreateWindow),
	XRootWindow:    type_of(xlib.XRootWindow),
	XDefaultScreen: type_of(xlib.XDefaultScreen),
	XDefaultScreenOfDisplay: type_of(xlib.XDefaultScreenOfDisplay),
	XDefaultVisual: type_of(xlib.XDefaultVisual),
	XStoreName:     type_of(xlib.XStoreName),
	XSetWMProtocols: type_of(xlib.XSetWMProtocols),
	XInternAtom:    type_of(xlib.XInternAtom),
	XSelectInput:   type_of(xlib.XSelectInput),
	XMapRaised:     type_of(xlib.XMapRaised),
	XWithdrawWindow: type_of(xlib.XWithdrawWindow),
	XDestroyWindow: type_of(xlib.XDestroyWindow),
}

X11_Window :: struct {
	handle:    xlib.Window,
	screen_no: i32,
}

x11_try_init :: proc() -> bool {
	log.debugf("Looking for X11 display")
	display_str: string
	found: bool
	if display_str, found = os.lookup_env("DISPLAY", g.talloc); !found {
		log.errorf("X11 display not found.")
		return false
	}
	display_cstr := strings.clone_to_cstring(display_str, g.talloc)
	log.debugf("Trying to load libX11.so")
	loaded: bool
	if g.x11.library, loaded = dynlib.load_library("libX11.so", false); !loaded {
		log.errorf("libX11.so not found.")
		return false
	}
	// Load symbols
	load_xsym(&g.x11.XOpenDisplay, "XOpenDisplay") or_return
	load_xsym(&g.x11.XCloseDisplay, "XCloseDisplay") or_return
	load_xsym(&g.x11.XCreateWindow, "XCreateWindow") or_return
	load_xsym(&g.x11.XRootWindow, "XRootWindow") or_return
	load_xsym(&g.x11.XDefaultScreen, "XDefaultScreen") or_return
	load_xsym(&g.x11.XDefaultScreenOfDisplay, "XDefaultScreenOfDisplay") or_return
	load_xsym(&g.x11.XDefaultVisual, "XDefaultVisual") or_return
	load_xsym(&g.x11.XStoreName, "XStoreName") or_return
	load_xsym(&g.x11.XSetWMProtocols, "XSetWMProtocols") or_return
	load_xsym(&g.x11.XInternAtom, "XInternAtom") or_return
	load_xsym(&g.x11.XSelectInput, "XSelectInput") or_return
	load_xsym(&g.x11.XMapRaised, "XMapRaised") or_return
	load_xsym(&g.x11.XWithdrawWindow, "XWithdrawWindow") or_return
	load_xsym(&g.x11.XDestroyWindow, "XDestroyWindow") or_return
	// Initialize X11 connection.
	g.x11.display = g.x11.XOpenDisplay(display_cstr)
	if g.x11.display == nil {
		log.errorf("Unable to Open X11 display.")
		return false
	}
	// Load atoms
	g.x11.wm_delete = g.x11.XInternAtom(g.x11.display, "WM_DELETE_WINDOW", false)
	return true
	load_xsym :: proc(dst: ^$T, name: string) -> (bool) {
		sym, loaded := dynlib.symbol_address(g.x11.library, name)
		if !loaded {
			log.errorf("Unable to find symbol %s in the libX11 library.", name)
			return false
		}
		dst^ = cast(T) sym
		return true
	}
}

x11_terminate :: proc() {
	// Close the connection to X11 server
	g.x11.XCloseDisplay(g.x11.display)
	// Unload the X11 library.
	if !dynlib.unload_library(g.x11.library) {
		log.errorf("Did not unload the X11 library.")
	}
}

x11_window_create :: proc(hints: ^Window_Hints) -> ^Window {
	screen_no := g.x11.XDefaultScreen(g.x11.display)
	size_x := hints.size_x
	size_y := hints.size_y
	pos_x  := hints.position_x
	pos_y  := hints.position_y
	// Set the specific values for the hints if they are marked DONT_CARE.
	if size_x == DONT_CARE {
		size_x = 1280
	}
	if size_y == DONT_CARE {
		size_y = 720
	}
	screen_handle := g.x11.XDefaultScreenOfDisplay(g.x11.display)
	if pos_x == DONT_CARE {
		pos_x = (cast(int) screen_handle.width - size_x) / 2
	}
	if pos_y == DONT_CARE {
		pos_y = (cast(int) screen_handle.height - size_y) / 2
	}
	log.debugf("Trying to create a window pos = (%d, %d), size = %d x %d",
		pos_x, pos_y, size_x, size_y,
	)
	// Create the window.
	window := new(Window, g.palloc)
	visual := g.x11.XDefaultVisual(g.x11.display, screen_no)
	root_window := g.x11.XRootWindow(g.x11.display, screen_no)
	attr: xlib.XSetWindowAttributes
	attr.override_redirect = false
	attr_mask := xlib.WindowAttributeMask{.CWOverrideRedirect}
	window.x11.screen_no = screen_no
	window.x11.handle = g.x11.XCreateWindow(
		g.x11.display,
		root_window,
		cast(i32) pos_x,
		cast(i32) pos_y,
		cast(u32) size_x,
		cast(u32) size_y,
		1,
		24,
		.CopyFromParent,
		visual,
		attr_mask,
		&attr)
	if window.x11.handle == 0 {
		free(window)
		return nil
	}
	// Set the window title.
	title_cstr, err := strings.clone_to_cstring(hints.title, g.talloc)
	if err != nil {
		x11_window_destroy(window)
		return nil
	}
	g.x11.XStoreName(g.x11.display, window.x11.handle, title_cstr)
	// Allow the window to be closed.
	status := g.x11.XSetWMProtocols(g.x11.display, window.x11.handle, &g.x11.wm_delete, 1)
	if status != nil {
		x11_window_destroy(window)
		return nil
	}
	// Set the event mask for the window regarding which events we want to receive.
	g.x11.XSelectInput(g.x11.display, window.x11.handle, {
        .SubstructureNotify, .StructureNotify,
        .ButtonPress, .ButtonRelease,
        .KeyPress,    .KeyRelease,
        .EnterWindow, .LeaveWindow,
        .PointerMotion,
        .ButtonMotion,
        .KeymapState,
        .FocusChange,
        .PropertyChange,
        .Exposure,
	})
	// Show the window.
	g.x11.XMapRaised(g.x11.display, window.x11.handle)
	return window
}

x11_window_destroy :: proc(window: ^Window) {
	g.x11.XDestroyWindow(g.x11.display, window.x11.handle)
	free(window)
}
