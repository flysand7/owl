package owl

import "core:time"
import "core:mem"
import "core:log"

@(private)
g: Global_State

@(private)
Global_State :: struct {
	using _: OS_Global_State,
	palloc:  mem.Allocator,
	talloc:  mem.Allocator,
	log:     log.Logger,
	windows: [dynamic]^Window,
}

/*
Errors returned by this library.
*/
Error :: enum {
	// No error.
	None,
	// Window manager not found. This can happen during library initialization, if
	// `$WAYLAND_DISPLAY` nor `$DISPLAY` environment variable isn't set.
	No_Window_Manager,
	// A bug in the library implementation, underlying OS or the allocator that has been
	// passed to the library is too small to handle all the data we're allocating.
	Out_Of_Memory,
}

/*
Initialization hints.
*/
Init_Hints :: bit_set[Init_Hint_Bit]
Init_Hint_Bit :: enum {
	// Enable internal logging.
	Logger,
	// Prefer X11 context, if available. This option is ignored on non-linux platforms.
	Linux_X11,
	// Prefer wayland context, if available. This option is ignored on non-linux platforms.
	Linux_Wayland,
}

/*
Library initialization.

## Description

You **must** initialize the library in order to use it. The functions that require the library
to be initialized do not perform checks of whether it is initialized, most likely the behavior
upon using the library without initialization is a crash.

The logger is set from the context. If `.Logger` is not specified in hints, the logger argument
is ignored.

For internal allocations the library uses allocations that can be overridden once during library
initialization. The allocators can be overridden by the user. The library allocates memory **only**
using the allocators set by the init function.

The permanent allocator must implement `.Free` and `.Resize` modes. The library manages the
permanent allocator. User should not manually free anything that is allocated using the permanent
allocator. No requirements are imposed for temporary allocator. The user can use `.Free_All`
function to free all allocations made by this library on per-frame basis. The library explicitly
documents whether values returned to the user are temporary or permanent and whether they are
allowed to be freed. Though in most situations temporary allocations don't reach the user.

The library may do allocations outside of the scope of the provided allocators, for example when it
calls into libc or Xlib (linux) functions that allocate memory under the hood. Freeing the
allocators manually does not free all the memory. Call `terminate()` to ensure everything that has
been allocated by the library is freed.

## Remark (linux)

This function will detect the presence of wayland and x11 on the system based on the current
type of the session, according to `$WAYLAND_DISPLAY` and `$DISPLAY` environment variables. The
check is done as follows:

1. First, `$WAYLAND_DISPLAY` environment variable is checked. If set, the value is used as
the wayland display. If unset or wayland initialization failed, we proceed to the second step.

2. The `$DISPLAY` environment variable is checked. If set, the value is used as the x11
display. If unset or x11 initialization failed, the `.No_Window_Manager` error is returned.

If `Init_Hints` specifies x11 or wayland, the order of steps is changed such that the
respective window manager is checked first.

## Synchronization

This function is not synchronized. Do not call it from multiple threads.

## Errors

- `No_Window_Manager` is returned, if no window manager was found, or none of avialable window
	managers could be initialized successfully.
*/
init :: proc(
	hints:     Init_Hints,
	logger     := context.logger,
	perm_alloc := context.allocator,
	temp_alloc := context.temp_allocator,
	loc        := #caller_location
) -> Error {
	context.logger = logger
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
	// Initialize the windows dynamic array
	allocation_err: mem.Allocator_Error
	g.windows, allocation_err = make_dynamic_array([dynamic]^Window, g.palloc)
	if allocation_err != nil {
		assert(allocation_err == .Out_Of_Memory, "Something is wrong")
		log.fatalf("Failed to allocate the array for windows: %v", allocation_err)
		return .Out_Of_Memory
	}
	return os_init(hints, logger, perm_alloc, temp_alloc, loc)
}

/*
Library termination.

## Description

This function terminates the library. Frees all the resources initialized by the library, destroys
all resources that were allocated by the library etc.

This function does not free objects allocated in the temporary allocator. It is the user's
responsibility to manage the temporary allocator whenever objects allocated by the library in
temporary storage are no longer needed.

It is possible to initialize and terminate the library multiple times.

**DO NOT** call this function if `init` returned an error.

## Synchronization

This function is not thread safe.
*/
terminate :: proc() {
	context.logger = g.log
	for window in g.windows {
		os_window_destroy(window)
		free(window)
	}
	delete(g.windows)
	os_terminate()
}

/*
Value for some parameters specifying that the library should pick a value. The places where this
value is allowed are explicitly documented.
*/
DONT_CARE := min(int)

/*
Hints for window initialization.
*/
Window_Hints :: struct {
	title: string,
	position_x: int,
	position_y: int,
	size_x: int,
	size_y: int,
}

/*
Return a default set of hints.

## Description

This procedure returns the set of default window hints. The values are as follows:
- `title`: `"OWL Window"`
- `position_x`: `DONT_CARE`
- `position_y`: `DONT_CARE`
- `size_x`: `DONT_CARE`
- `size_y`: `DONT_CARE`
*/
hints_default :: proc() -> Window_Hints {
	return {
		title = "OWL Window",
		position_x = DONT_CARE,
		position_y = DONT_CARE,
		size_x = DONT_CARE,
		size_y = DONT_CARE,
	}
}

/*
Specify that you want a specific title on your window.

## Lifetimes

The provided string must be alive during the time between specifying this hint is specified and the
call to `create_window()`. The library borrows the string for that period. During the call to
`create_window()`, this string may be transformed to a cstring using the temporary allocator.
*/
hint_title :: proc(hints: ^Window_Hints, title: string) {
	hints.title = title
}

/*
Specify that you want a window at a specific position.

## Description

This procedure sets the desired position of the window, in screen coordinates, or, if `DONT_CARE`
is specified for either coordinate, the window is displayed such that it is centered. The default
value of this hint is `DONT_CARE`.

In case a coordinate is specified, the position values must be non-negative.
*/
hint_position :: proc(hints: ^Window_Hints, position_x: int, position_y: int) {
	hints.position_x = position_x
	hints.position_y = position_y
}

/*
Specify that a window needs to have a specific size.

## Description

This procedure sets the desired size of the window, in screen coordinates, or, if `DONT_CARE` is
specified for either coordinate, the window's size is chosen to be 1280x720.

## Remark (tiled window managers)

In case a tiled window manager is used (typically on linux), the window size can not be controlled
by the user and instead is decided by the window manager. Do not assume that the size of the window
is the same as you asked it to be with this hint, always verify the size after the window has been
created.
*/
hint_size :: proc(hints: ^Window_Hints, size_x: int, size_y: int) {
	hints.size_x = size_x
	hints.size_y = size_y
}

/*
Callback to track window position changes.
*/
Window_Callback_Position :: #type proc(window: ^Window, position_x: int, position_y: int)

/*
Callback to track window size changes.
*/
Window_Callback_Size :: #type proc(window: ^Window, size_x: int, size_y: int)

/*
Mouse movement callback. `position_x` and `position_y` specify the mouse position, in window
coordinates.
*/
Window_Callback_Mouse :: #type proc(window: ^Window, position_x: int, position_y: int)

/*
Window hovering callback. `entered` is true, if the cursor has just entered the window, and `false`
if the cursor has just left the window's bounds.
*/
Window_Callback_Crossing :: #type proc(window: ^Window, entered: bool)

/*
Window focus callback. `focused` is true, if the window became enfocused, `false` if it went out
of focus.
*/
Window_Callback_Focus :: #type proc(window: ^Window, focused: bool)

/*
Semi-opaque structure representing a window.
*/
Window :: struct {
	using _:      OS_Window,
	size_x:       int,
	size_y:       int,
	position_x:   int,
	position_y:   int,
	should_close: bool,
	cb_position:  Window_Callback_Position,
	cb_size:      Window_Callback_Size,
	cb_mouse:     Window_Callback_Mouse,
	cb_crossing:  Window_Callback_Crossing,
	cb_focus:     Window_Callback_Focus,
}

/*
Create the window.

## Params
- `hints`: The set of hints to provide for window initialization, or `nil` to use the default.

## Description

This function creates the window and returns a semi-opaque pointer to the `window` structure.
Look at documentation for the hint-initialization function to know which options are available.

Here's a short example of how you can use this function to create a window.

```
hints := owl.hints_default()
owl.hint_position(&hints, 0, 0)
owl.hint_size(&hints, 1280, 720)
owl.hint_title(&hints, "My cool-ass title")
window := create_window(&hints)
assert(window != nil, "Window creation failed")
```

## Thread-safety

This procedure is not thread-safe as long as allocation procedures of the specified permanent
allocator are not synchronized.
*/
window_create :: proc(hints: ^Window_Hints) -> ^Window {
	context.logger = g.log
	window: ^Window
	if hints == nil {
		default_hints := hints_default()
		window = os_window_create(&default_hints)
	} else {
		window = os_window_create(hints)
	}
	if window != nil {
		append(&g.windows, window)
	}
	return window
}

/*
Check whether window should close.

## Description

When the user presses the 'X' button in the titlebar or makes a request for the window to close
otherwise, the library sets `should_close` flag to `true`. You can check whether this flag is set
in the event loop to only loop until this window is closed.
*/
window_should_close :: proc(window: ^Window) -> bool {
	return window.should_close
}

/*
Set the window position callback.

## Description

This procedure sets the callback that will be called when window position is changed.
*/
window_position_callback :: proc(window: ^Window, callback: Window_Callback_Position) {
	window.cb_position = callback
}

/*
Set the window size callback.

## Description

This procedure sets the callback that will be called when window size is changed.
*/
window_size_callback :: proc(window: ^Window, callback: Window_Callback_Size) {
	window.cb_size = callback
}

/*
Set the window hover callback.

## Description

This procedure sets the window crossing callback that is called when the mouse enters or leaves
the bounds of the specified window.
*/
window_hover_callback :: proc(window: ^Window, callback: Window_Callback_Crossing) {
	window.cb_crossing = callback
}

/*
Set the window mouse movement callback.

## Description

This procedure sets the window mouse movement callback that is called when the mouse moves within
the bounds of the specified window.
*/
window_mouse_callback :: proc(window: ^Window, callback: Window_Callback_Mouse) {
	window.cb_mouse = callback
}

/*
Set the window focus callback.

## Description

This procedure sets the window focus callback. It is called when the windows enters or leaves the
focus.
*/
window_focus_callback :: proc(window: ^Window, callback: Window_Callback_Focus) {
	window.cb_focus = callback
}

/*
Destroy a window.

## Description

This procedure closes the window and deallocates the associated memory. You can call this function
when the window is open or closed, and the window is guaranteed to be destroyed.

You can not call any procedures using the destroyed window as a parameter.

## Lifetimes

Do not call this procedures from within any callbacks. Most likely you are handling events in a
loop. If one of the events in the queue destroyed the window, receiving the next event from the
event queue will dereference a null-pointer.
*/
window_destroy :: proc(window: ^Window) {
	context.logger = g.log
	os_window_destroy(window)
	free(window)
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

/*
When duration is expected as a timeout for waiting, this value signifies that waiting is
indefinite.
*/
DURATION_INDEFINITE :: time.MIN_DURATION

/*
Blocks the calling thread until an event has been delivered, or the timeout expires

## Description

This procedure blocks the calling thread until the next event has been delivered via callbacks. If
the duration is specified as `DURATION_INDEFINITE`, the waiting is indefinite and does not time out.

In case duration is not indefinite, it must be a positive value.

## Returns

`true` if the event was delivered, `false` if the event wasn't delivered or/and timeout expired.
*/
wait_event :: proc(timeout := DURATION_INDEFINITE) -> b32 {
	context.logger = g.log
	return os_wait_event(timeout)
}

/*
Checks if there are any events in the queue, and handles them only if there are any.

## Description

This procedure checks to see if there are any events in the event queue. If there are no events,
this procedure returns `false`, otherwise it handles the events present and returns `true`. Unlike
`wait_event` this function does not block if there are no events in the queue.
*/
poll_events :: proc() -> bool {
	context.logger = g.log
	return os_poll_events()
}
