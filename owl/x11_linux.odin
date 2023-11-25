//+private, +build linux
package owl

import "core:os"
import "core:log"
import "core:dynlib"
import "core:strings"

import "vendor:x11/xlib"

X11_State :: struct {
	library:       dynlib.Library,
	display:       ^xlib.Display,
	XOpenDisplay:  type_of(xlib.XOpenDisplay),
	XCloseDisplay: type_of(xlib.XCloseDisplay),
	XCreateWindow: type_of(xlib.XCreateWindow),
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
	// Initialize X11 connection.
	g.x11.display = g.x11.XOpenDisplay(display_cstr)
	if g.x11.display == nil {
		log.errorf("Unable to Open X11 display.")
		return false
	}	
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
